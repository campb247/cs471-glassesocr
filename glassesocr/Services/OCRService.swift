// filename: ocrservice.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis

import Vision
import UIKit

/// commercial baseline ocr using apple's on device vision framework
/// wraps vnrecognizetextrequest with timing instrumentation
/// returned text is whatever vision recognized end to end (detection plus recognition)
class OCRService {

    /// recognizes text in given image and reports wall clock inference time
    /// completion fires on main thread with:
    ///   text: recognized string, or nil if vision found nothing
    ///   timeMs: full request to result latency in milliseconds
    func recognizeText(in image: UIImage,
                       completion: @escaping (String?, Double) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil, 0)
            return
        }

        // capture start time before request setup
        // ensures we measure full apple vision overhead, not just inference
        let start = CFAbsoluteTimeGetCurrent()

        let request = VNRecognizeTextRequest { request, error in
            // elapsed measured at completion regardless of success path
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

            if let error = error {
                print("OCR error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil, elapsedMs) }
                return
            }

            // joins all detected text observations with spaces
            // vision may return multiple boxes for multi line content
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")

            // logs to syslog for benchmarking analysis
            // nslog used instead of print since print sometimes hidden by xcode filters
            NSLog("[OCRService] Apple Vision: %.1f ms  → \"%@\"", elapsedMs, text)

            DispatchQueue.main.async {
                completion(text.isEmpty ? nil : text, elapsedMs)
            }
        }

        // .accurate is slower but more precise than .fast
        // single character demos benefit from accuracy more than throughput
        request.recognitionLevel = .accurate

        // language correction biases vision against single isolated characters
        // (treats them as not text)
        // disabled here for fair single char comparison vs charactercnn
        request.usesLanguageCorrection = false

        // perform request off main thread to avoid ui stalls
        // request handler runs synchronously; dispatch wraps it
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                print("Failed to perform OCR: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(nil, elapsedMs) }
            }
        }
    }
}
