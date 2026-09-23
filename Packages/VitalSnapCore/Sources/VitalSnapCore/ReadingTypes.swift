import Foundation

public enum ReadingKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case weight
    case bloodPressure

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .weight: return "Weight"
        case .bloodPressure: return "Blood pressure"
        }
    }
}

public enum MassUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case pounds
    case kilograms

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .pounds: return "lb"
        case .kilograms: return "kg"
        }
    }

    public var name: String {
        switch self {
        case .pounds: return "Pounds"
        case .kilograms: return "Kilograms"
        }
    }

    public func converted(_ value: Double, to other: MassUnit) -> Double {
        if self == other { return value }
        switch (self, other) {
        case (.pounds, .kilograms):
            return value * 0.45359237
        case (.kilograms, .pounds):
            return value / 0.45359237
        default:
            return value
        }
    }
}

public struct WeightReading: Equatable, Sendable {
    public var value: Double
    public var unit: MassUnit
    public var confidence: Double
    public var evidence: String
    public var unitWasInferred: Bool

    public init(
        value: Double,
        unit: MassUnit,
        confidence: Double,
        evidence: String,
        unitWasInferred: Bool
    ) {
        self.value = value
        self.unit = unit
        self.confidence = confidence
        self.evidence = evidence
        self.unitWasInferred = unitWasInferred
    }
}

public struct BloodPressureReading: Equatable, Sendable {
    public var systolic: Double
    public var diastolic: Double
    public var pulse: Double?
    public var confidence: Double
    public var evidence: String

    public init(
        systolic: Double,
        diastolic: Double,
        pulse: Double?,
        confidence: Double,
        evidence: String
    ) {
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
        self.confidence = confidence
        self.evidence = evidence
    }
}

public enum ReadingFormat {
    public static func weight(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0f", value)
        }
        if abs((value * 10).rounded() - (value * 10)) < 0.001 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    public static func whole(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    public static func lenientDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
}
