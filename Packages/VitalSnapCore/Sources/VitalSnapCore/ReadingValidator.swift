import Foundation

public struct FieldValidation: Equatable, Sendable {
    public var canSave: Bool
    public var blockingMessage: String?
    public var caution: String?

    public init(canSave: Bool, blockingMessage: String? = nil, caution: String? = nil) {
        self.canSave = canSave
        self.blockingMessage = blockingMessage
        self.caution = caution
    }
}

public enum ReadingValidator {
    public static func validate(_ draft: ReadingDraft) -> FieldValidation {
        switch draft.kind {
        case .weight:
            return validateWeight(draft)
        case .bloodPressure:
            return validateBloodPressure(draft)
        }
    }

    private static func validateWeight(_ draft: ReadingDraft) -> FieldValidation {
        guard let value = draft.weightValue else {
            return FieldValidation(canSave: false, blockingMessage: "Enter the weight shown on the scale.")
        }
        switch draft.weightUnit {
        case .kilograms:
            guard value >= 5, value <= 320 else {
                return FieldValidation(
                    canSave: false,
                    blockingMessage: "Enter a weight from 5 to 320 kg."
                )
            }
            if value < 30 || value > 250 {
                return FieldValidation(
                    canSave: true,
                    caution: "This is outside the range most home scales show. Save it only if it matches the display."
                )
            }
        case .pounds:
            guard value >= 10, value <= 700 else {
                return FieldValidation(
                    canSave: false,
                    blockingMessage: "Enter a weight from 10 to 700 lb."
                )
            }
            if value < 66 || value > 550 {
                return FieldValidation(
                    canSave: true,
                    caution: "This is outside the range most home scales show. Save it only if it matches the display."
                )
            }
        }
        return FieldValidation(canSave: true)
    }

    private static func validateBloodPressure(_ draft: ReadingDraft) -> FieldValidation {
        guard let systolic = draft.systolicValue, let diastolic = draft.diastolicValue else {
            return FieldValidation(canSave: false, blockingMessage: "Enter both systolic and diastolic numbers.")
        }
        guard systolic >= 70, systolic <= 250, diastolic >= 40, diastolic <= 150 else {
            return FieldValidation(
                canSave: false,
                blockingMessage: "Systolic must be 70–250 and diastolic 40–150."
            )
        }
        guard systolic > diastolic else {
            return FieldValidation(canSave: false, blockingMessage: "Systolic needs to be higher than diastolic.")
        }
        guard systolic - diastolic >= 10 else {
            return FieldValidation(
                canSave: false,
                blockingMessage: "Those two numbers are too close together to save as a blood pressure."
            )
        }
        if let pulse = draft.pulseValue, pulse < 30 || pulse > 220 {
            return FieldValidation(
                canSave: false,
                blockingMessage: "Pulse needs to be between 30 and 220, or leave it blank."
            )
        }
        if systolic >= 180 || systolic < 90 || diastolic >= 110 || diastolic < 60 {
            return FieldValidation(
                canSave: true,
                caution: "This is outside a common home range. Save it only if it matches the display."
            )
        }
        return FieldValidation(canSave: true)
    }
}
