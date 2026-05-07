// filename: streamviewmodel.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis

import SwiftUI
import Combine
import MWDATCore
import MWDATCamera

/// owns mwdat stream session, ocr pipeline, and tts output
/// bridges streamsessionview and testmodeview to underlying services
/// runs on main actor since published properties drive ui
@MainActor
class StreamViewModel: ObservableObject {

    // MARK: published state (drives ui)

    // current sdk session state (stopped, starting, streaming, etc)
    @Published var streamState: StreamSessionState = .stopped
    // most recent preview frame, updated at throttled rate
    @Published var currentFrame: UIImage?
    // apple vision result text for most recent capture
    @Published var appleResult: String = ""
    // charactercnn result formatted as "label  (xx%)"
    @Published var customResult: String = ""
    // 28x28 grayscale image actually fed to cnn (debug overlay)
    @Published var customModelInput: UIImage?
    // wall clock latency of last apple vision call in milliseconds
    @Published var appleTimeMs: Double = 0
    // pure cnn forward pass time in milliseconds (excludes preprocessing)
    @Published var customTimeMs: Double = 0
    // true while ocr is in flight, disables read button to prevent overlap
    @Published var isProcessingOCR: Bool = false
    // surfaces sdk or processing errors to view
    @Published var errorMessage: String?

    // MARK: private services

    private let ocrService = OCRService()
    private let customOCRService = CustomOCRService()
    private let ttsService = TTSService()

    // active mwdat session, nil when not streaming
    private var session: StreamSession?

    // listener tokens MUST be retained as instance variables
    // sdk uses weak references internally; releasing tokens cancels subscriptions
    // (took us a while to figure out why callbacks suddenly stopped firing)
    private var stateToken: AnyListenerToken?
    private var frameToken: AnyListenerToken?
    private var errorToken: AnyListenerToken?
    private var photoToken: AnyListenerToken?

    // throttle preview image updates so we do not burn main thread
    // converting every frame
    // capture quality is unaffected since we capture via separate path
    private var lastFrameTime: Date = .distantPast
    private let framePreviewInterval: TimeInterval = 0.1  // ~10 hz ui updates

    // MARK: session control

    /// starts mwdat stream session and wires up event listeners
    /// configures stream at 15 fps; 30 fps overwhelmed sdk pipeline causing freezes
    func startSession(deviceSelector: AutoDeviceSelector) {
        // 15 fps is plenty for ocr preview and reduces sdk pressure
        // empirically, 30 fps caused stream to stall after about 30 seconds
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .high,
            frameRate: 15
        )

        let session = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)
        self.session = session

        // subscribe to session state transitions
        // mirrors sdk state into published streamState for ui
        stateToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                self?.streamState = state
            }
        }

        // subscribe to incoming video frames
        // throttled so we update currentFrame at most once per framePreviewInterval
        frameToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                // skip frame if last update was within throttle window
                guard now.timeIntervalSince(self.lastFrameTime) >= self.framePreviewInterval else { return }
                self.lastFrameTime = now
                self.currentFrame = frame.makeUIImage()
            }
        }

        // surface stream level errors to ui
        // (typical examples: glasses out of range, low battery, ble timeout)
        errorToken = session.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                self?.errorMessage = "\(error)"
            }
        }

        // photo data publisher fires when capturePhoto completes
        // currently unused since we use preview frames for ocr
        // kept wired up so future high quality capture path works
        photoToken = session.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let image = UIImage(data: photoData.data) else {
                    self.isProcessingOCR = false
                    self.appleResult = "Failed to decode photo."
                    self.customResult = "—"
                    return
                }
                self.runComparison(on: image)
            }
        }

        Task { await session.start() }
    }

    /// stops session and releases listener tokens
    /// safe to call multiple times; clearSession idempotent
    func stopSession() {
        Task {
            await session?.stop()
            clearSession()
        }
    }

    // MARK: ocr plus tts pipeline

    /// captures most recent live preview frame and runs ocr on it
    /// preview is more reliable than capturePhoto for our purposes:
    ///   capturePhoto sometimes returns malformed data on permission edge cases
    ///   preview gives user "what you see is what gets processed" semantics
    func captureAndRead() {
        // guard against double tap during in flight ocr
        guard !isProcessingOCR else { return }

        // need at least one frame from stream before we can capture
        guard let frame = currentFrame else {
            ttsService.speak("No frame available — wait for the stream.")
            return
        }

        isProcessingOCR = true
        appleResult = "Processing…"
        customResult = "Processing…"
        runComparison(on: frame)
    }

    /// test mode entry point: runs comparison on supplied uiimage
    /// used by testmodeview when user picks photo from library
    /// no glasses session required (calls runComparison directly)
    func processImage(_ image: UIImage) {
        guard !isProcessingOCR else { return }
        isProcessingOCR = true
        appleResult = "Processing…"
        customResult = "Processing…"
        runComparison(on: image)
    }

    /// runs both ocr services on same character crop
    /// vision detects largest character box once
    /// both classifiers receive identical crop for fair comparison
    /// when vision finds nothing, cnn falls back to its own pipeline
    /// while apple panel shows "no character detected"
    private func runComparison(on image: UIImage) {
        // bake in camera frame's orientation metadata
        // vision normalized coords and cgimage.cropping(to:) must operate in same space
        // ble delivered frames sometimes carry .right or .down orientation
        // without normalization, resulting crop is offset or partial
        let oriented = image.orientationNormalized()

        // run vision once to find character box
        // both services then operate on this exact crop
        // (or oriented full image if vision found nothing)
        let visionCrop = customOCRService.cropToLargestCharacter(in: oriented)
        let target = visionCrop ?? oriented
        let visionDetected = (visionCrop != nil)

        // dispatchgroup synchronizes results from two parallel ocr calls
        // notify fires once both completions have run
        let group = DispatchGroup()

        // apple vision branch
        group.enter()
        ocrService.recognizeText(in: target) { [weak self] text, timeMs in
            guard let self else { group.leave(); return }
            self.appleTimeMs = timeMs
            if let text, !text.isEmpty {
                self.appleResult = text
            } else {
                // distinguish "vision detected box but recognition rejected it"
                // from "vision found no text region at all"
                self.appleResult = visionDetected
                    ? "No character recognized"
                    : "No character detected"
            }
            group.leave()
        }

        // shared handler for both cnn paths (fast and fallback)
        // updates result, debug image, and timing in one place
        group.enter()
        let cnnHandler: (CustomOCRResult?) -> Void = { [weak self] result in
            guard let self else { group.leave(); return }
            if let result {
                self.customResult = "\(result.label)  (\(Int(result.confidence * 100))%)"
                self.customModelInput = result.modelInput
                self.customTimeMs = result.inferenceTimeMs
            } else {
                self.customResult = "—"
                self.customModelInput = nil
                self.customTimeMs = 0
            }
            group.leave()
        }

        if visionDetected {
            // fast path: pre cropped input, just classify
            customOCRService.classifyCroppedCharacter(in: target, completion: cnnHandler)
        } else {
            // fallback: cnn does its own segmentation (center crop, threshold)
            // result for this trial is technically not directly comparable to apple
            customOCRService.recognizeCharacter(in: image, completion: cnnHandler)
        }

        // when both completions are done, finish ui state and announce result
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isProcessingOCR = false
            // speak whichever apple vision returned
            // skip tts for "no character" results to avoid spammy negatives
            if !self.appleResult.hasPrefix("No character") && !self.appleResult.isEmpty {
                self.ttsService.speak(self.appleResult)
            } else {
                self.ttsService.speak("No character detected.")
            }
        }
    }

    /// stops in flight tts utterance
    func stopSpeaking() {
        ttsService.stop()
    }

    // MARK: helpers

    /// releases session and listener tokens
    /// must release tokens to break sdk's strong references and allow cleanup
    private func clearSession() {
        session = nil
        stateToken = nil
        frameToken = nil
        errorToken = nil
        photoToken = nil
    }
}
