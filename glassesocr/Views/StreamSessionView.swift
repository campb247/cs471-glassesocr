// filename: streamsessionview.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis
// date: may 7 2026

import SwiftUI
import MWDATCore
import MWDATCamera

/// main screen shown after registration and camera permission are granted
/// shows live preview from glasses camera
/// tapping read text runs both ocr services on most recent frame
/// results display side by side with timing and cnn input debug overlay
struct StreamSessionView: View {

    @ObservedObject var wearablesVM: WearablesViewModel

    // streamviewmodel owns the mwdat session and ocr pipeline
    // creating it inside this view ensures it lives for screen's lifetime
    @StateObject private var streamVM = StreamViewModel()

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: camera feed
                ZStack {
                    Color.black.ignoresSafeArea(edges: .top)

                    if let frame = streamVM.currentFrame {
                        Image(uiImage: frame)
                            .resizable()
                            .scaledToFit()
                    } else {
                        // placeholder while waiting for first frame
                        // (stream takes 1 to 2 seconds to start)
                        VStack(spacing: 12) {
                            ProgressView().tint(Theme.primaryLight)
                            Text(statusLabel)
                                .font(Theme.mono(13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }

                    // debug overlay: 28x28 grayscale image fed to cnn
                    // helps diagnose preprocessing issues during demo
                    // interpolation set to none so pixels show crisp blocks
                    if let modelInput = streamVM.customModelInput {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("CNN INPUT")
                                .font(Theme.mono(10, weight: .semibold))
                                .foregroundStyle(.white)
                                .tracking(1.0)
                            Image(uiImage: modelInput)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.primaryLight, lineWidth: 1.5)
                                )
                        }
                        .padding(8)
                        .background(.black.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                    }
                }
                .frame(maxHeight: .infinity)

                // MARK: controls
                VStack(spacing: 16) {

                    // side by side comparison panels
                    // each shows service name, timing, and prediction
                    HStack(alignment: .top, spacing: 10) {
                        resultPanel(title: "APPLE VISION",
                                    text: streamVM.appleResult,
                                    timeMs: streamVM.appleTimeMs)
                        resultPanel(title: "CHARACTER CNN",
                                    text: streamVM.customResult,
                                    timeMs: streamVM.customTimeMs)
                    }
                    .frame(height: 130)

                    // action buttons row
                    HStack(spacing: 10) {
                        // primary cta: triggers ocr on current preview frame
                        Button {
                            streamVM.captureAndRead()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: streamVM.isProcessingOCR ? "hourglass" : "text.viewfinder")
                                Text(streamVM.isProcessingOCR ? "Processing…" : "Read Text")
                            }
                            .themedPrimaryButton()
                            .opacity((!isStreaming || streamVM.isProcessingOCR) ? 0.5 : 1)
                        }
                        .buttonStyle(.plain)
                        // disabled if no stream available or another ocr call is in flight
                        .disabled(!isStreaming || streamVM.isProcessingOCR)

                        // interrupts current tts utterance
                        Button {
                            streamVM.stopSpeaking()
                        } label: {
                            Image(systemName: "speaker.slash")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.primaryDark)
                                .padding(14)
                                .background(Theme.primaryLight.opacity(0.4),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        // unregisters glasses and stops stream
                        // returns user to registrationview
                        Button {
                            streamVM.stopSession()
                            wearablesVM.unregister()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 17))
                                .foregroundStyle(Theme.danger)
                                .padding(14)
                                .background(Theme.danger.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    // shows whichever error is freshest
                    // stream errors take priority over wearables errors
                    if let error = streamVM.errorMessage ?? wearablesVM.errorMessage {
                        Text(error)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .background(Theme.surface)
            }
        }
        // start session when view appears, stop when it disappears
        // prevents wasted bluetooth bandwidth on backgrounded sessions
        .onAppear {
            streamVM.startSession(deviceSelector: wearablesVM.deviceSelector)
        }
        .onDisappear {
            streamVM.stopSession()
        }
    }

    // MARK: helpers

    /// reusable card displaying ocr service title, timing, and result text
    /// timeMs of zero suppresses timing label (cleaner pre capture state)
    /// uses minimumScaleFactor so longer apple results shrink rather than truncate
    private func resultPanel(title: String, text: String, timeMs: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(Theme.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.primaryDark)
                Spacer()
                if timeMs > 0 {
                    // sub millisecond cnn times need decimal precision
                    // larger apple times round to whole milliseconds for tidiness
                    Text(timeMs < 10 ? String(format: "%.1f ms", timeMs)
                                     : String(format: "%.0f ms", timeMs))
                        .font(Theme.mono(10, weight: .regular))
                        .foregroundStyle(Theme.primaryDark.opacity(0.6))
                }
            }
            Text(text.isEmpty ? "—" : text)
                .font(Theme.mono(20, weight: .regular))
                .foregroundStyle(Theme.primaryDark)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            // pushes content to top of card; spacer absorbs leftover height
            Spacer(minLength: 0)
        }
        // frame must come before themedcard so card background fills full panel
        // otherwise card paints background at vstack natural size and gets clipped
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedCard()
    }

    // shorthand for "stream is producing live frames"
    // disables read text button until this is true
    private var isStreaming: Bool {
        streamVM.streamState == .streaming
    }

    // human readable label for current stream state
    // shown over black placeholder before first frame arrives
    private var statusLabel: String {
        switch streamVM.streamState {
        case .stopped:           return "Stream stopped"
        case .waitingForDevice:  return "Waiting for glasses…"
        case .starting:          return "Connecting…"
        case .streaming:         return "Streaming"
        case .paused:            return "Paused"
        case .stopping:          return "Stopping…"
        @unknown default:        return "Unknown state"
        }
    }
}
