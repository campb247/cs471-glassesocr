// filename: customocrservice.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis
// date: may 7 2026

import CoreML
import UIKit
import CoreGraphics
import CoreImage
import Vision

/// bundled output of charactercnn prediction
/// includes 28x28 model input image so ui can show what cnn actually saw
/// timing fields support per call benchmarking against apple vision
struct CustomOCRResult {
    // top predicted class label (one of 62 chars: 0-9, A-Z, a-z)
    let label: String
    // softmax probability for predicted class, in [0, 1]
    let confidence: Float
    // 28x28 grayscale buffer rendered as uiimage for debug display
    let modelInput: UIImage?
    // pure model forward pass time, no preprocessing
    let inferenceTimeMs: Double
    // end to end including preprocessing and pixel buffer creation
    let totalTimeMs: Double
}

/// single character ocr using charactercnn trained on chars74k fnt
/// model expects 28x28 grayscale image of one centered character
/// covers 62 classes (digits 0-9, uppercase A-Z, lowercase a-z)
/// pipeline: vision finds character bbox, we crop and preprocess, cnn classifies
class CustomOCRService {

    // auto generated wrapper around .mlpackage bundled in app
    private let model: CharacterCNN

    init() {
        do {
            self.model = try CharacterCNN(configuration: MLModelConfiguration())
        } catch {
            // crashing here is intentional
            // app cannot function without ml model loaded
            fatalError("Failed to load CharacterCNN model: \(error)")
        }
    }

    /// full pipeline: vision detection, crop to largest char, preprocess, classify
    /// falls back to center crop or whole image if vision finds nothing
    /// this path is used when caller wants cnn to handle its own segmentation
    func recognizeCharacter(in image: UIImage,
                            completion: @escaping (CustomOCRResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // chained fallback strategy:
            //   1. vision detected character box (best, most accurate crop)
            //   2. center crop at 60% (assumes user centered character)
            //   3. whole image (last resort, rarely useful)
            let cropped = self.cropToLargestCharacter(in: image)
                ?? self.centerCrop(image, ratio: 0.6)
                ?? image
            let result = self.classify(cropped)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// classify only path
    /// caller already has clean character crop
    /// used by streamviewmodel when vision crop is shared with apple ocrservice
    /// for apples to apples comparison on identical input
    func classifyCroppedCharacter(in image: UIImage,
                                  completion: @escaping (CustomOCRResult?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.classify(image)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// runs preprocessing, model forward pass, and softmax extraction
    /// returns nil if preprocessing fails (e.g. malformed cgimage)
    private func classify(_ croppedImage: UIImage) -> CustomOCRResult? {
        let totalStart = CFAbsoluteTimeGetCurrent()

        guard let pixelBuffer = preprocess(croppedImage) else { return nil }

        // capture debug image of exactly what model sees
        // useful for diagnosing bad crops live during demo
        let modelInput = uiImage(fromGrayscaleBuffer: pixelBuffer)

        do {
            // measure pure inference time separately from preprocessing
            // gives clean number for speed comparison slide
            let inferenceStart = CFAbsoluteTimeGetCurrent()
            let output = try model.prediction(image: pixelBuffer)
            let inferenceMs = (CFAbsoluteTimeGetCurrent() - inferenceStart) * 1000

            let label = output.classLabel
            let confidence = softmaxConfidence(for: label, output: output)
            let totalMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000

            // syslog log for benchmarking pipelines
            NSLog("[CustomOCRService] CharacterCNN: %.2f ms inference, %.2f ms total  → '%@' (%.0f%%)",
                  inferenceMs, totalMs, label, confidence * 100)

            return CustomOCRResult(label: label,
                                   confidence: confidence,
                                   modelInput: modelInput,
                                   inferenceTimeMs: inferenceMs,
                                   totalTimeMs: totalMs)
        } catch {
            print("CustomOCR error: \(error.localizedDescription)")
            return nil
        }
    }

    /// converts raw 28x28 grayscale pixel buffer to uiimage for debug display
    /// uses ciimage as intermediate since cgimage cannot directly read cvpixelbuffer
    private func uiImage(fromGrayscaleBuffer buffer: CVPixelBuffer) -> UIImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: vision based segmentation

    /// uses vnrecognizetextrequest to find character bounding boxes
    /// returns crop of largest detected character with 25% margin
    /// only consumes vision's boxes, not its recognized text
    /// (classification is still cnn's job)
    /// returns nil if vision found no text at all
    func cropToLargestCharacter(in image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) }
        catch { return nil }

        guard let observations = request.results as? [VNRecognizedTextObservation],
              !observations.isEmpty else { return nil }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        // collect every character level box across all observations
        // falls back to observation level box if per character boxes fail
        // (some vision builds do not expose char level bounding boxes)
        var charBoxes: [CGRect] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string
            var added = 0
            for (offset, _) in text.enumerated() {
                let start = text.index(text.startIndex, offsetBy: offset)
                let end = text.index(after: start)
                if let rect = try? candidate.boundingBox(for: start..<end) {
                    charBoxes.append(rect.boundingBox.toImageRect(width: imageW, height: imageH))
                    added += 1
                }
            }
            // if per char boxes failed for this observation, use whole observation box
            if added == 0 {
                charBoxes.append(obs.boundingBox.toImageRect(width: imageW, height: imageH))
            }
        }

        // pick box with largest area (most likely to be intended subject)
        guard let largest = charBoxes.max(by: { $0.area < $1.area }) else { return nil }

        // expand by 25% so character has training like padding around it
        // chars74k samples sit centered with white margin
        // matching that distribution improves cnn accuracy
        let mx = largest.width * 0.125
        let my = largest.height * 0.125
        let expanded = CGRect(
            x: largest.minX - mx,
            y: largest.minY - my,
            width: largest.width + 2 * mx,
            height: largest.height + 2 * my
        ).intersection(CGRect(x: 0, y: 0, width: imageW, height: imageH))

        guard !expanded.isEmpty,
              let cropped = cgImage.cropping(to: expanded) else { return nil }
        return UIImage(cgImage: cropped)
    }

    /// crops to centered square at given fraction of original image
    /// used as fallback when vision finds no text
    /// assumes user roughly centered intended character in viewfinder
    private func centerCrop(_ image: UIImage, ratio: CGFloat) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let cropW = w * ratio
        let cropH = h * ratio
        let rect = CGRect(x: (w - cropW) / 2, y: (h - cropH) / 2,
                          width: cropW, height: cropH)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }

    // MARK: confidence (softmax)

    /// recovers proper probability from raw logits in classifier output
    /// coremltools mlprogram converter does not always insert softmax on classifier outputs
    /// so probabilities dict can hold unbounded logit values
    /// we apply softmax over all values to get clean probability for displayed class
    private func softmaxConfidence(for label: String, output: CharacterCNNOutput) -> Float {
        // iterates feature names since probabilities key name varies by export
        // (sometimes classlabelprobs, sometimes classlabel_probs, etc)
        for name in output.featureNames where name != "classLabel" {
            guard let raw = output.featureValue(for: name)?.dictionaryValue,
                  !raw.isEmpty else { continue }

            // copy nsnumber dict into typed swift dict for math
            var values: [String: Float] = [:]
            for (k, v) in raw {
                if let key = k as? String { values[key] = v.floatValue }
            }
            // skip features that do not contain expected label key
            guard !values.isEmpty, values[label] != nil else { continue }

            // numerical stability trick: subtract max before exp
            // prevents overflow when logits are large
            let m = values.values.max() ?? 0
            let exps = values.mapValues { exp($0 - m) }
            let sum = exps.values.reduce(0, +)
            guard sum > 0 else { return 0 }
            return (exps[label] ?? 0) / sum
        }
        return 0
    }

    // MARK: preprocessing

    /// converts cropped uiimage into 28x28 grayscale cvpixelbuffer for cnn input
    /// pipeline:
    ///   1. render full image to grayscale bytes
    ///   2. compute mean brightness to detect polarity (dark on light vs light on dark)
    ///   3. threshold to find tight bounding box of "ink" pixels
    ///   4. pad bbox to square plus 20% margin (mimics chars74k distribution)
    ///   5. crop, resize to 28x28, optionally invert if light on dark input
    private func preprocess(_ image: UIImage) -> CVPixelBuffer? {
        guard let cgIn = image.cgImage else { return nil }

        // render to single channel grayscale buffer
        // we threshold this directly rather than via core image for speed
        let w = cgIn.width
        let h = cgIn.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &bytes, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cgIn, in: CGRect(x: 0, y: 0, width: w, height: h))

        // mean brightness decides polarity:
        // > 128 implies dark text on light background (typical printed text)
        // < 128 implies light text on dark background (signs, screens)
        let mean = bytes.reduce(0) { $0 + Int($1) } / max(1, bytes.count)
        let darkOnLight = mean > 128

        // threshold offset of 40 reliably separates ink from background
        // (calibrated against chars74k samples and real glasses captures)
        let threshold = darkOnLight ? max(0, mean - 40) : min(255, mean + 40)

        // walk every pixel, accumulate tight bbox of ink locations
        // using primitive int comparisons; faster than core image filters at this size
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w
            for x in 0..<w {
                let p = Int(bytes[row + x])
                let isInk = darkOnLight ? (p < threshold) : (p > threshold)
                if isInk {
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        // produce final crop rect
        // either tight padded bbox or center crop fallback
        let bbox: CGRect
        if maxX < minX || maxY < minY {
            // no ink found, fall back to center crop of largest square that fits
            let side = min(w, h)
            bbox = CGRect(x: (w - side) / 2, y: (h - side) / 2,
                          width: side, height: side)
        } else {
            // pad to square (longer side) with extra 20% margin
            // 1.4 multiplier gives roughly 20% padding on each side
            let bw = maxX - minX + 1
            let bh = maxY - minY + 1
            let side = Int(Double(max(bw, bh)) * 1.4)
            let cx = minX + bw / 2
            let cy = minY + bh / 2
            var x0 = cx - side / 2
            var y0 = cy - side / 2
            // clamp to image bounds so cgcontext does not get negative coords
            x0 = max(0, min(w - side, x0))
            y0 = max(0, min(h - side, y0))
            let s = min(side, min(w, h))
            bbox = CGRect(x: x0, y: y0, width: s, height: s)
        }

        guard let cropped = cgIn.cropping(to: bbox) else { return nil }

        // render cropped glyph into 28x28 buffer (final cnn input)
        // invert flag flips polarity if input was light on dark
        // training data is uniformly dark on light, so model expects that
        return makeGrayscalePixelBuffer(from: cropped, side: 28, invert: !darkOnLight)
    }

    /// renders cgimage into preallocated cvpixelbuffer of given side length
    /// optionally inverts pixel intensities so model sees expected polarity
    private func makeGrayscalePixelBuffer(from cg: CGImage,
                                          side: Int,
                                          invert: Bool) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        // create single channel 8 bit buffer (matches model input format)
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, side, side,
            kCVPixelFormatType_OneComponent8,
            attrs as CFDictionary, &pb
        )
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        // lock buffer for direct memory write; defer ensures unlock on all paths
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bpr = CVPixelBufferGetBytesPerRow(buffer)
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: base, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // high quality interpolation matters for small targets (28x28)
        // default produces visibly worse downsample compared to high
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        // invert pixel intensities in place if needed
        // training data is dark glyph on white background
        // input that is light on dark gets flipped here so model sees expected distribution
        if invert {
            let pixels = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<side {
                let row = y * bpr
                for x in 0..<side {
                    pixels[row + x] = 255 &- pixels[row + x]
                }
            }
        }

        return buffer
    }
}

// MARK: helper extensions

private extension CGRect {
    // shorthand for area calculation, used when picking largest bbox
    var area: CGFloat { width * height }

    /// converts vision normalized rect (origin bottom left, in [0, 1])
    /// into image pixel coordinates (origin top left, in [0, width or height])
    /// vision uses opencv style bottom up coords; cgimage is top down
    func toImageRect(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: minX * width,
            y: (1 - minY - self.height) * height,
            width: self.width * width,
            height: self.height * height
        )
    }
}

extension UIImage {
    /// re draws image with orientation baked into pixel data
    /// after this call, cgimage returns pixels in displayed orientation
    /// required before running vision and cgimage.cropping(to:) together
    /// because vision normalized coords and cgimage cropping must operate in same space
    /// otherwise crops come out partial or offset (camera frames often arrive as .right)
    func orientationNormalized() -> UIImage {
        // skip rerender if already in canonical orientation
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
