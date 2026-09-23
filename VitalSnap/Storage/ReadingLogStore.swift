import Foundation
import VitalSnapCore

struct LoggedReading: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: ReadingKind
    var summary: String
    var detail: String
    var capturedAt: Date
    var savedToHealth: Bool
    var note: String
    var weightValue: Double? = nil
    var weightUnit: MassUnit? = nil
    var systolic: Double? = nil
    var diastolic: Double? = nil
    var pulse: Double? = nil
}

@MainActor
@Observable
final class ReadingLogStore {
    private(set) var readings: [LoggedReading] = []
    private let fileURL: URL?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let base {
            let folder = base.appendingPathComponent("VitalSnap", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            fileURL = folder.appendingPathComponent("readings.json")
        } else {
            fileURL = nil
        }
        load()
    }

    init(previewReadings: [LoggedReading]) {
        readings = previewReadings
        fileURL = nil
    }

    @discardableResult
    func add(from draft: ReadingDraft, savedToHealth: Bool, note: String) -> LoggedReading {
        let entry = LoggedReading(
            id: UUID(),
            kind: draft.kind,
            summary: draft.summary ?? draft.kind.title,
            detail: draft.detail,
            capturedAt: draft.capturedAt,
            savedToHealth: savedToHealth,
            note: note,
            weightValue: draft.kind == .weight ? draft.weightValue : nil,
            weightUnit: draft.kind == .weight ? draft.weightUnit : nil,
            systolic: draft.systolicValue,
            diastolic: draft.diastolicValue,
            pulse: draft.pulseValue
        )
        readings.insert(entry, at: 0)
        if readings.count > 100 {
            readings.removeLast(readings.count - 100)
        }
        persist()
        return entry
    }

    func remove(_ id: UUID) {
        readings.removeAll { $0.id == id }
        persist()
    }

    func markSavedToHealth(_ id: UUID) {
        guard let index = readings.firstIndex(where: { $0.id == id }) else { return }
        readings[index].savedToHealth = true
        readings[index].note = "Saved to Apple Health."
        persist()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        readings = (try? decoder.decode([LoggedReading].self, from: data)) ?? []
    }

    private func persist() {
        guard let fileURL, let data = try? encoder.encode(readings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension LoggedReading {
    static var previewSamples: [LoggedReading] {
        [
            LoggedReading(
                id: UUID(),
                kind: .weight,
                summary: "184.6 lb",
                detail: "Pounds",
                capturedAt: Date().addingTimeInterval(-3600),
                savedToHealth: true,
                note: "Saved to Apple Health."
            ),
            LoggedReading(
                id: UUID(),
                kind: .bloodPressure,
                summary: "128/82 mmHg",
                detail: "Pulse 74 bpm",
                capturedAt: Date().addingTimeInterval(-86_400),
                savedToHealth: false,
                note: "Saved on this iPhone. Apple Health was not available."
            ),
        ]
    }
}
