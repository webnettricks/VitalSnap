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
    /// Reads the photo on device. If the first pass does not yield a reading,
    /// a higher-contrast copy is tried once.
    static func recognizeBest(_ image: UIImage, kind: ReadingKind) async throws -> [RecognizedLine] {
        let prepared = image.preparedForOCR()
        guard let cgImage = prepared.cgImage else { throw OCRError.unreadable }
        let first = try await perform(on: cgImage)
        if ReadingParser.parse(kind: kind, lines: first).hasReading {
            return first
        }
        guard let enhanced = contrasted(cgImage) else { return first }
        let second = try await perform(on: enhanced)
        if ReadingParser.parse(kind: kind, lines: second).hasReading {
            return second
        }
        return second.count > first.count ? second : first
    }

    private static func perform(on cgImage: CGImage) async throws -> [RecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
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

    private static func contrasted(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0, forKey: kCIInputSaturationKey)
        filter.setValue(1.35, forKey: kCIInputContrastKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: nil).createCGImage(output, from: output.extent)
    }
}

extension UIImage {
    /// Bakes orientation into the pixels and caps the long edge so Vision stays responsive.
    func preparedForOCR() -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longest = max(pixelWidth, pixelHeight)
        let maxSide: CGFloat = 2000
        let factor = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: max(pixelWidth * factor, 1), height: max(pixelHeight * factor, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
