import Foundation

/// One line of text produced by on-device OCR.
///
/// Coordinates use Vision's normalized space: origin at the bottom-left, values from 0 to 1.
/// Pass zeros when the position is unknown; parsers then keep the array order.
public struct RecognizedLine: Equatable, Sendable, Codable {
    public var text: String
    public var confidence: Double
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        text: String,
        confidence: Double = 1,
        x: Double = 0,
        y: Double = 0,
        width: Double = 0,
        height: Double = 0
    ) {
        self.text = text
        self.confidence = confidence
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Top edge in Vision coordinates. Larger values sit higher on the photo.
    public var top: Double { y + height }
}
