import Foundation
import HealthKit
import VitalSnapCore

enum HealthWriteResult: Equatable {
    case saved
    case unavailable
    case denied
    case failed(String)
}

/// Writes confirmed readings into Apple Health. Samples are marked user-entered
/// because a person checked the OCR result before saving.
final class HealthStoreService {
    private let store = HKHealthStore()
    private let metadata: [String: Any] = [
        HKMetadataKeyWasUserEntered: true,
    ]

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func save(_ draft: ReadingDraft) async -> HealthWriteResult {
        guard isAvailable else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
        } catch {
            return .failed(error.localizedDescription)
        }
        if isDenied(for: draft.kind) {
            return .denied
        }
        do {
            switch draft.kind {
            case .weight:
                guard let value = draft.weightValue else {
                    return .failed("Enter a weight before saving.")
                }
                try await saveWeight(value, unit: draft.weightUnit, date: draft.capturedAt)
            case .bloodPressure:
                guard let systolic = draft.systolicValue, let diastolic = draft.diastolicValue else {
                    return .failed("Enter both blood pressure numbers before saving.")
                }
                try await saveBloodPressure(
                    systolic: systolic,
                    diastolic: diastolic,
                    pulse: draft.pulseValue,
                    date: draft.capturedAt
                )
            }
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
            HKQuantityType(.heartRate),
            HKCorrelationType(.bloodPressure),
        ]
    }

    private func isDenied(for kind: ReadingKind) -> Bool {
        let type: HKObjectType
        switch kind {
        case .weight:
            type = HKQuantityType(.bodyMass)
        case .bloodPressure:
            type = HKCorrelationType(.bloodPressure)
        }
        return store.authorizationStatus(for: type) == .sharingDenied
    }

    private func saveWeight(_ value: Double, unit: MassUnit, date: Date) async throws {
        let healthUnit: HKUnit = unit == .pounds ? .pound() : .gramUnit(with: .kilo)
        let quantity = HKQuantity(unit: healthUnit, doubleValue: value)
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: quantity,
            start: date,
            end: date,
            metadata: metadata
        )
        try await store.save(sample)
    }

    private func saveBloodPressure(systolic: Double, diastolic: Double, pulse: Double?, date: Date) async throws {
        let millimeters = HKUnit.millimeterOfMercury()
        let systolicSample = HKQuantitySample(
            type: HKQuantityType(.bloodPressureSystolic),
            quantity: HKQuantity(unit: millimeters, doubleValue: systolic),
            start: date,
            end: date,
            metadata: metadata
        )
        let diastolicSample = HKQuantitySample(
            type: HKQuantityType(.bloodPressureDiastolic),
            quantity: HKQuantity(unit: millimeters, doubleValue: diastolic),
            start: date,
            end: date,
            metadata: metadata
        )
        let correlation = HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: date,
            end: date,
            objects: [systolicSample, diastolicSample],
            metadata: metadata
        )
        try await store.save(correlation)

        if let pulse {
            let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
            let heartRate = HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: beatsPerMinute, doubleValue: pulse),
                start: date,
                end: date,
                metadata: metadata
            )
            try await store.save(heartRate)
        }
    }
}
