import CoreImage
import UIKit
import Vision
import VitalSnapCore

enum OCRError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        "This photo could not be read. Type the numbers from the display."
    }
}

enum TextRecognizer {
    private static let context = CIContext(options: nil)

    /// Reads the photo on device. `kind` is the mode chosen on the home screen
    /// (weight or blood pressure) and is the same value the review parser uses.
    ///
    /// When the first pass returns lines but no reading, LCD-oriented copies are
    /// tried: higher contrast, sharpen, and invert. The copy with the strongest
    /// parse wins. If none of them parse, the richest transcript is kept so the
    /// review screen can show it while the person types.
    static func recognizeBest(_ image: UIImage, kind: ReadingKind) async throws -> [RecognizedLine] {
        let prepared = image.preparedForOCR()
        guard let cgImage = prepared.cgImage else { throw OCRError.unreadable }

        let first = try await perform(on: cgImage)
        if ReadingParser.parse(kind: kind, lines: first).hasReading {
            return first
        }

        var bestLines: [RecognizedLine]?
        var bestConfidence = 0.0
        var richest = first
        for variant in lcdVariants(of: cgImage) {
            let lines = try await perform(on: variant)
            if transcriptLength(lines) > transcriptLength(richest) {
                richest = lines
            }
            let confidence = readingConfidence(lines, kind: kind)
            if confidence > bestConfidence {
                bestConfidence = confidence
                bestLines = lines
            }
            if bestConfidence >= 0.85, let bestLines {
                return bestLines
            }
        }
        if let bestLines, bestConfidence > 0 {
            return bestLines
        }
        return richest
    }

    private static func readingConfidence(_ lines: [RecognizedLine], kind: ReadingKind) -> Double {
        let result = ReadingParser.parse(kind: kind, lines: lines)
        switch kind {
        case .bloodPressure:
            return result.bloodPressure?.confidence ?? 0
        case .weight:
            return result.weight?.confidence ?? 0
        }
    }

    private static func transcriptLength(_ lines: [RecognizedLine]) -> Int {
        lines.reduce(0) { $0 + $1.text.count }
    }

    private static func perform(on cgImage: CGImage) async throws -> [RecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0
            request.customWords = ["mmHg", "SYS", "DIA", "PUL", "PULSE", "kg", "lb", "lbs"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            return observations.compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return RecognizedLine(
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    x: box.origin.x,
                    y: box.origin.y,
                    width: box.width,
                    height: box.height
                )
            }
        }.value
    }

    /// Light-on-dark and dark-on-light LCDs both show up in home photos.
    /// Invert is last so a normal backlit panel is tried before it.
    private static func lcdVariants(of image: CGImage) -> [CGImage] {
        [
            filtered(image, contrast: 1.35, brightness: 0.05, sharpness: 0, invert: false),
            filtered(image, contrast: 2.1, brightness: 0.02, sharpness: 0.7, invert: false),
            filtered(image, contrast: 1.5, brightness: 0, sharpness: 0.4, invert: true),
            filtered(image, contrast: 2.2, brightness: 0.04, sharpness: 0.8, invert: true),
        ].compactMap { $0 }
    }

    private static func filtered(
        _ image: CGImage,
        contrast: Double,
        brightness: Double,
        sharpness: Double,
        invert: Bool
    ) -> CGImage? {
        var output = CIImage(cgImage: image)
        if invert {
            guard let filter = CIFilter(name: "CIColorInvert") else { return nil }
            filter.setValue(output, forKey: kCIInputImageKey)
            guard let inverted = filter.outputImage else { return nil }
            output = inverted
        }
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(output, forKey: kCIInputImageKey)
        controls.setValue(0, forKey: kCIInputSaturationKey)
        controls.setValue(contrast, forKey: kCIInputContrastKey)
        controls.setValue(brightness, forKey: kCIInputBrightnessKey)
        guard let adjusted = controls.outputImage else { return nil }
        output = adjusted
        if sharpness > 0, let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(output, forKey: kCIInputImageKey)
            sharpen.setValue(sharpness, forKey: kCIInputSharpnessKey)
            if let sharpened = sharpen.outputImage {
                output = sharpened
            }
        }
        let extent = output.extent
        guard !extent.isInfinite, !extent.isNull else { return nil }
        return context.createCGImage(output, from: extent)
    }
}

extension UIImage {
    /// Bakes orientation into the pixels and caps the long edge so Vision stays responsive.
    func preparedForOCR() -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longest = max(pixelWidth, pixelHeight)
        let maxSide: CGFloat = 2200
        let factor: CGFloat
        if longest > maxSide {
            factor = maxSide / longest
        } else if longest > 0, longest < 1000 {
            factor = min(2, 1600 / longest)
        } else {
            factor = 1
        }
        let target = CGSize(width: max(pixelWidth * factor, 1), height: max(pixelHeight * factor, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
