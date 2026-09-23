import Foundation

/// Fixed OCR transcripts used by the sample buttons and the parser tests.
public enum SampleDisplay {
    public static let scale: [RecognizedLine] = [
        RecognizedLine(text: "12:41"),
        RecognizedLine(text: "WEIGHT"),
        RecognizedLine(text: "184.6", confidence: 0.98),
        RecognizedLine(text: "lb", confidence: 0.93),
        RecognizedLine(text: "BMI 24.8"),
        RecognizedLine(text: "FAT 21.4%"),
    ]

    public static let cuff: [RecognizedLine] = [
        RecognizedLine(text: "SYS"),
        RecognizedLine(text: "mmHg"),
        RecognizedLine(text: "128", confidence: 0.98),
        RecognizedLine(text: "DIA"),
        RecognizedLine(text: "mmHg"),
        RecognizedLine(text: "82", confidence: 0.97),
        RecognizedLine(text: "PULSE"),
        RecognizedLine(text: "/min"),
        RecognizedLine(text: "74", confidence: 0.9),
    ]
}
