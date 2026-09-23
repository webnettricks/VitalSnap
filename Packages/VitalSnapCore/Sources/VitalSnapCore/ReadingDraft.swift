import Foundation

/// Editable reading shown on the confirm screen. Values are strings so a person can fix a digit.
public struct ReadingDraft: Equatable, Sendable {
    public var kind: ReadingKind
    public var weightText: String
    public var weightUnit: MassUnit
    public var systolicText: String
    public var diastolicText: String
    public var pulseText: String
    public var rawText: String
    public var note: String
    public var warnings: [String]
    public var capturedAt: Date

    public init(
        kind: ReadingKind,
        weightText: String = "",
        weightUnit: MassUnit = .pounds,
        systolicText: String = "",
        diastolicText: String = "",
        pulseText: String = "",
        rawText: String = "",
        note: String = "",
        warnings: [String] = [],
        capturedAt: Date
    ) {
        self.kind = kind
        self.weightText = weightText
        self.weightUnit = weightUnit
        self.systolicText = systolicText
        self.diastolicText = diastolicText
        self.pulseText = pulseText
        self.rawText = rawText
        self.note = note
        self.warnings = warnings
        self.capturedAt = capturedAt
    }

    public static func make(kind: ReadingKind, lines: [RecognizedLine], capturedAt: Date = Date()) -> ReadingDraft {
        let result = ReadingParser.parse(kind: kind, lines: lines)
        var draft = ReadingDraft(
            kind: kind,
            rawText: result.rawText,
            note: result.note,
            warnings: result.warnings,
            capturedAt: capturedAt
        )
        if let weight = result.weight {
            draft.weightText = ReadingFormat.weight(weight.value)
            draft.weightUnit = weight.unit
        }
        if let bloodPressure = result.bloodPressure {
            draft.systolicText = ReadingFormat.whole(bloodPressure.systolic)
            draft.diastolicText = ReadingFormat.whole(bloodPressure.diastolic)
            if let pulse = bloodPressure.pulse {
                draft.pulseText = ReadingFormat.whole(pulse)
            }
        }
        return draft
    }

    public var weightValue: Double? { ReadingFormat.lenientDouble(weightText) }
    public var systolicValue: Double? { ReadingFormat.lenientDouble(systolicText) }
    public var diastolicValue: Double? { ReadingFormat.lenientDouble(diastolicText) }
    public var pulseValue: Double? {
        let trimmed = pulseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ReadingFormat.lenientDouble(trimmed)
    }

    public var summary: String? {
        switch kind {
        case .weight:
            guard let weightValue else { return nil }
            return "\(ReadingFormat.weight(weightValue)) \(weightUnit.symbol)"
        case .bloodPressure:
            guard let systolicValue, let diastolicValue else { return nil }
            return "\(ReadingFormat.whole(systolicValue))/\(ReadingFormat.whole(diastolicValue)) mmHg"
        }
    }

    public var detail: String {
        switch kind {
        case .weight:
            return weightUnit.name
        case .bloodPressure:
            if let pulseValue {
                return "Pulse \(ReadingFormat.whole(pulseValue)) bpm"
            }
            return "No pulse entered"
        }
    }
}
