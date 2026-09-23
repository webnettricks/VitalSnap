import Foundation

public struct ParseResult: Equatable, Sendable {
    public var weight: WeightReading?
    public var bloodPressure: BloodPressureReading?
    public var warnings: [String]
    public var rawText: String
    public var note: String

    public var hasReading: Bool {
        weight != nil || bloodPressure != nil
    }
}

public enum ReadingParser {
    public static func parse(kind: ReadingKind, lines: [RecognizedLine]) -> ParseResult {
        let rawText = ReadingOrder.rawText(lines)
        switch kind {
        case .weight:
            return parseWeight(lines: lines, rawText: rawText)
        case .bloodPressure:
            return parseBloodPressure(lines: lines, rawText: rawText)
        }
    }

    private static func parseWeight(lines: [RecognizedLine], rawText: String) -> ParseResult {
        var weight = WeightParser.parse(lines: lines)
        let bloodPressure = BloodPressureParser.parse(lines: lines)
        var warnings: [String] = []

        if let bloodPressure, bloodPressure.confidence >= 0.75, weight == nil || weight?.unitWasInferred == true {
            weight = nil
            warnings.append("These numbers look like blood pressure. Switch the reading type if this is a cuff.")
        }

        if let weight {
            if weight.unitWasInferred {
                warnings.append("The unit was not readable. Confirm pounds or kilograms.")
            }
            let note = "Matched \(weight.evidence) on the display."
            return ParseResult(weight: weight, bloodPressure: nil, warnings: warnings, rawText: rawText, note: note)
        }

        if warnings.isEmpty {
            warnings.append("No weight was found. Type the number shown on the scale.")
        }
        return ParseResult(
            weight: nil,
            bloodPressure: nil,
            warnings: warnings,
            rawText: rawText,
            note: "No weight could be read from the photo."
        )
    }

    private static func parseBloodPressure(lines: [RecognizedLine], rawText: String) -> ParseResult {
        let weight = WeightParser.parse(lines: lines)
        var bloodPressure = BloodPressureParser.parse(lines: lines)
        var warnings: [String] = []

        if let weight, weight.unitWasInferred == false, bloodPressure == nil || (bloodPressure?.confidence ?? 0) < 0.7 {
            bloodPressure = nil
            warnings.append("These numbers look like a weight. Switch the reading type if this is a scale.")
        }

        if let bloodPressure {
            if bloodPressure.confidence < 0.7 {
                warnings.append("Labels were not found. Check which number is systolic and which is diastolic.")
            }
            var note = "Matched \(bloodPressure.evidence)."
            if let pulse = bloodPressure.pulse {
                note += " Pulse \(ReadingFormat.whole(pulse))."
            }
            return ParseResult(weight: nil, bloodPressure: bloodPressure, warnings: warnings, rawText: rawText, note: note)
        }

        if warnings.isEmpty {
            warnings.append("No blood pressure was found. Type the numbers shown on the cuff.")
        }
        return ParseResult(
            weight: nil,
            bloodPressure: nil,
            warnings: warnings,
            rawText: rawText,
            note: "No blood pressure could be read from the photo."
        )
    }
}
