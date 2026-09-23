import XCTest
@testable import VitalSnapCore

final class ParserTests: XCTestCase {
    func testScaleSample() {
        let reading = WeightParser.parse(lines: SampleDisplay.scale)
        XCTAssertEqual(reading?.value, 184.6)
        XCTAssertEqual(reading?.unit, .pounds)
        XCTAssertEqual(reading?.unitWasInferred, false)

        let draft = ReadingDraft.make(kind: .weight, lines: SampleDisplay.scale, capturedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(draft.weightValue, 184.6)
        XCTAssertEqual(draft.weightUnit, .pounds)
        XCTAssertTrue(draft.warnings.isEmpty)
        XCTAssertTrue(ReadingValidator.validate(draft).canSave)
    }

    func testCuffSample() {
        let reading = BloodPressureParser.parse(lines: SampleDisplay.cuff)
        XCTAssertEqual(reading?.systolic, 128)
        XCTAssertEqual(reading?.diastolic, 82)
        XCTAssertEqual(reading?.pulse, 74)
        XCTAssertGreaterThan(reading?.confidence ?? 0, 0.7)

        let draft = ReadingDraft.make(kind: .bloodPressure, lines: SampleDisplay.cuff, capturedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(draft.systolicValue, 128)
        XCTAssertEqual(draft.diastolicValue, 82)
        XCTAssertEqual(draft.pulseValue, 74)
        XCTAssertEqual(draft.summary, "128/82 mmHg")
        XCTAssertTrue(ReadingValidator.validate(draft).canSave)
    }

    func testWeightUnitsAndNoise() {
        XCTAssertEqual(WeightParser.parse(lines: lines(["83.7 kg"]))?.value, 83.7)
        XCTAssertEqual(WeightParser.parse(lines: lines(["83.7 kg"]))?.unit, .kilograms)

        let stacked = WeightParser.parse(lines: lines(["72.4", "kg"]))
        XCTAssertEqual(stacked?.value, 72.4)
        XCTAssertEqual(stacked?.unit, .kilograms)
        XCTAssertEqual(stacked?.unitWasInferred, false)

        let noisy = WeightParser.parse(lines: lines([
            "12:41",
            "FAT 22.3%",
            "BMI 24.1",
            "75.2 kg",
            "MUSCLE 40.1%",
        ]))
        XCTAssertEqual(noisy?.value, 75.2)
        XCTAssertEqual(noisy?.unit, .kilograms)
    }

    func testEuropeanDecimalAndOCRRepairs() {
        let comma = WeightParser.parse(lines: lines(["83,4 kg"]))
        XCTAssertEqual(comma?.value ?? 0, 83.4, accuracy: 0.001)
        XCTAssertEqual(comma?.unit, .kilograms)

        let letterO = WeightParser.parse(lines: lines(["8O.5 kg"]))
        XCTAssertEqual(letterO?.value ?? 0, 80.5, accuracy: 0.001)

        let misreadUnit = WeightParser.parse(lines: lines(["72.4 k9"]))
        XCTAssertEqual(misreadUnit?.value, 72.4)
        XCTAssertEqual(misreadUnit?.unit, .kilograms)

        let poundsMisread = WeightParser.parse(lines: lines(["184.6 1b"]))
        XCTAssertEqual(poundsMisread?.value, 184.6)
        XCTAssertEqual(poundsMisread?.unit, .pounds)

        let fullwidth = WeightParser.parse(lines: lines(["１８４．６ lb"]))
        XCTAssertEqual(fullwidth?.value ?? 0, 184.6, accuracy: 0.001)
    }

    func testStoneConversion() {
        let reading = WeightParser.parse(lines: lines(["11 st 4 lb"]))
        XCTAssertEqual(reading?.value, 158)
        XCTAssertEqual(reading?.unit, .pounds)
        XCTAssertEqual(reading?.unitWasInferred, false)

        let stonesOnly = WeightParser.parse(lines: lines(["9 stone"]))
        XCTAssertEqual(stonesOnly?.value, 126)
    }

    func testInferredUnits() {
        let heavy = WeightParser.parse(lines: lines(["184.6"]))
        XCTAssertEqual(heavy?.unit, .pounds)
        XCTAssertEqual(heavy?.unitWasInferred, true)

        let light = WeightParser.parse(lines: lines(["83.7"]))
        XCTAssertEqual(light?.unit, .kilograms)
        XCTAssertEqual(light?.unitWasInferred, true)

        let result = ReadingParser.parse(kind: .weight, lines: lines(["83.7"]))
        XCTAssertTrue(result.warnings.contains { $0.contains("unit") })
    }

    func testTallerNumberWinsWhenUnitIsMissing() {
        let reading = WeightParser.parse(lines: [
            RecognizedLine(text: "22.4", confidence: 0.9, x: 0.2, y: 0.7, width: 0.4, height: 0.06),
            RecognizedLine(text: "184.6", confidence: 0.9, x: 0.1, y: 0.4, width: 0.8, height: 0.24),
        ])
        XCTAssertEqual(reading?.value, 184.6)
    }

    func testIgnoresImplausibleWeight() {
        XCTAssertNil(WeightParser.parse(lines: lines(["4.2 kg"])))
        XCTAssertNil(WeightParser.parse(lines: lines(["12:41"])))
        XCTAssertNil(WeightParser.parse(lines: []))
    }

    func testUpperReadingWinsWhenBothUnitsArePrinted() {
        let reading = WeightParser.parse(lines: lines(["83.7 kg", "184.5 lb"]))
        XCTAssertEqual(reading?.unit, .kilograms)
        XCTAssertEqual(reading?.value, 83.7)
    }

    func testBloodPressureLayouts() {
        let slash = BloodPressureParser.parse(lines: lines(["128/82", "PULSE 74"]))
        XCTAssertEqual(slash?.systolic, 128)
        XCTAssertEqual(slash?.diastolic, 82)
        XCTAssertEqual(slash?.pulse, 74)

        let labels = BloodPressureParser.parse(lines: lines(["SYS 128", "DIA 82", "PUL 74"]))
        XCTAssertEqual(labels?.systolic, 128)
        XCTAssertEqual(labels?.diastolic, 82)
        XCTAssertEqual(labels?.pulse, 74)

        let oneLine = BloodPressureParser.parse(lines: lines(["SYS 128 DIA 82 PUL 74"]))
        XCTAssertEqual(oneLine?.systolic, 128)
        XCTAssertEqual(oneLine?.diastolic, 82)
        XCTAssertEqual(oneLine?.pulse, 74)

        let above = BloodPressureParser.parse(lines: lines(["128", "SYS", "82", "DIA", "74", "PULSE"]))
        XCTAssertEqual(above?.systolic, 128)
        XCTAssertEqual(above?.diastolic, 82)
        XCTAssertEqual(above?.pulse, 74)

        let over = BloodPressureParser.parse(lines: lines(["118 over 76", "HR 66"]))
        XCTAssertEqual(over?.systolic, 118)
        XCTAssertEqual(over?.diastolic, 76)
        XCTAssertEqual(over?.pulse, 66)

        let stacked = BloodPressureParser.parse(lines: lines(["128", "82", "74"]))
        XCTAssertEqual(stacked?.systolic, 128)
        XCTAssertEqual(stacked?.diastolic, 82)
        XCTAssertEqual(stacked?.pulse, 74)
        XCTAssertLessThan(stacked?.confidence ?? 1, 0.7)

        let merged = BloodPressureParser.parse(lines: lines(["128 82 74"]))
        XCTAssertEqual(merged?.systolic, 128)
        XCTAssertEqual(merged?.diastolic, 82)
        XCTAssertEqual(merged?.pulse, 74)
    }

    func testBloodPressureRejection() {
        XCTAssertNil(BloodPressureParser.parse(lines: lines(["12/31/2024"])))
        XCTAssertNil(BloodPressureParser.parse(lines: lines(["70/120"])))
        XCTAssertNil(BloodPressureParser.parse(lines: lines(["No reading"])))

        let optionalPulse = BloodPressureParser.parse(lines: lines(["120/80"]))
        XCTAssertEqual(optionalPulse?.systolic, 120)
        XCTAssertEqual(optionalPulse?.diastolic, 80)
        XCTAssertNil(optionalPulse?.pulse)
    }

    func testCrossTypeWarnings() {
        let asWeight = ReadingParser.parse(kind: .weight, lines: lines(["128/82", "PULSE 74"]))
        XCTAssertNil(asWeight.weight)
        XCTAssertTrue(asWeight.warnings.contains { $0.contains("blood pressure") })

        let asPressure = ReadingParser.parse(kind: .bloodPressure, lines: lines(["184.6 lb"]))
        XCTAssertNil(asPressure.bloodPressure)
        XCTAssertTrue(asPressure.warnings.contains { $0.contains("weight") })
    }

    func testValidationBounds() {
        XCTAssertFalse(validateWeight("", unit: .pounds).canSave)
        XCTAssertTrue(validateWeight("184.6", unit: .pounds).canSave)
        XCTAssertNil(validateWeight("184.6", unit: .pounds).caution)
        XCTAssertFalse(validateWeight("2", unit: .pounds).canSave)
        XCTAssertFalse(validateWeight("800", unit: .pounds).canSave)
        XCTAssertTrue(validateWeight("600", unit: .pounds).canSave)
        XCTAssertNotNil(validateWeight("600", unit: .pounds).caution)

        XCTAssertTrue(validatePressure(sys: "120", dia: "80", pulse: "").canSave)
        XCTAssertFalse(validatePressure(sys: "80", dia: "120", pulse: "").canSave)
        XCTAssertFalse(validatePressure(sys: "120", dia: "80", pulse: "400").canSave)
        XCTAssertTrue(validatePressure(sys: "120", dia: "80", pulse: "").canSave)
        XCTAssertFalse(validatePressure(sys: "50", dia: "30", pulse: "").canSave)
        let extreme = validatePressure(sys: "190", dia: "120", pulse: "74")
        XCTAssertTrue(extreme.canSave)
        XCTAssertNotNil(extreme.caution)
    }

    func testUnitConversion() {
        let kilograms = MassUnit.pounds.converted(158, to: .kilograms)
        XCTAssertEqual(kilograms, 158 * 0.45359237, accuracy: 0.0001)
        XCTAssertEqual(MassUnit.kilograms.converted(kilograms, to: .pounds), 158, accuracy: 0.001)
    }

    private func lines(_ texts: [String]) -> [RecognizedLine] {
        texts.map { RecognizedLine(text: $0, confidence: 0.95) }
    }

    private func validateWeight(_ text: String, unit: MassUnit) -> FieldValidation {
        ReadingValidator.validate(ReadingDraft(
            kind: .weight,
            weightText: text,
            weightUnit: unit,
            capturedAt: Date(timeIntervalSince1970: 0)
        ))
    }

    private func validatePressure(sys: String, dia: String, pulse: String) -> FieldValidation {
        ReadingValidator.validate(ReadingDraft(
            kind: .bloodPressure,
            systolicText: sys,
            diastolicText: dia,
            pulseText: pulse,
            capturedAt: Date(timeIntervalSince1970: 0)
        ))
    }
}
