import Foundation

/// Heuristic reader for home blood pressure cuff LCDs.
///
/// It understands `128/82`, SYS/DIA labels (including numbers on the next line),
/// and a plain stack of large digits. Pulse is kept only when a leftover number
/// or a pulse label is present.
public enum BloodPressureParser {
    public static func parse(lines: [RecognizedLine]) -> BloodPressureReading? {
        let ordered = ReadingOrder.normalized(lines).filter { !DisplayText.isDistractor($0.text) }
        let text = ordered.map(\.text).joined(separator: "\n")
        guard !text.isEmpty else { return nil }

        let fraction = findFraction(in: text)
        let labeled = findLabeled(in: ordered)

        if var fraction, let labeled {
            if fraction.systolic == labeled.systolic, fraction.diastolic == labeled.diastolic {
                fraction.pulse = fraction.pulse ?? labeled.pulse
                fraction.confidence = 0.95
                fraction.evidence = "\(ReadingFormat.whole(fraction.systolic))/\(ReadingFormat.whole(fraction.diastolic))"
                return fraction
            }
            return labeled
        }
        if var fraction {
            if fraction.pulse == nil {
                fraction.pulse = standalonePulse(in: text, systolic: fraction.systolic, diastolic: fraction.diastolic)
            }
            return fraction
        }
        if let labeled {
            return labeled
        }
        return findStack(in: ordered)
    }

    private static func isPlausible(systolic: Double, diastolic: Double) -> Bool {
        systolic >= 70 && systolic <= 250
            && diastolic >= 40 && diastolic <= 150
            && systolic > diastolic
            && (systolic - diastolic) >= 10
    }

    private static func findFraction(in text: String) -> BloodPressureReading? {
        let pattern = #"(?<![0-9.])(\d{2,3})\s*(?:/|over)\s*(\d{2,3})(?![0-9.])(?:\s*(?:/|over)\s*(\d{2,3})(?![0-9.]))?"#
        for groups in DisplayText.captures(in: text, pattern: pattern) {
            guard groups.count > 2,
                  let systolic = Double(groups[1]),
                  let diastolic = Double(groups[2]),
                  isPlausible(systolic: systolic, diastolic: diastolic) else { continue }
            var pulse: Double?
            if groups.count > 3, let extra = Double(groups[3]), isPulse(extra, systolic: systolic, diastolic: diastolic) {
                pulse = extra
            }
            return BloodPressureReading(
                systolic: systolic,
                diastolic: diastolic,
                pulse: pulse,
                confidence: pulse == nil ? 0.9 : 0.93,
                evidence: groups[0]
            )
        }
        return nil
    }

    private enum Marker: CaseIterable {
        case systolic, diastolic, pulse

        var pattern: String {
            switch self {
            case .systolic: return #"\b(?:systolic|sys|sbp)\b"#
            case .diastolic: return #"\b(?:diastolic|dias|dia|dbp)\b"#
            case .pulse: return #"\b(?:pulse|pul|bpm|hr)\b"#
            }
        }

        func accepts(_ value: Double) -> Bool {
            switch self {
            case .systolic: return value >= 70 && value <= 250
            case .diastolic: return value >= 40 && value <= 150
            case .pulse: return value >= 30 && value <= 220
            }
        }
    }

    private struct IndexedNumber {
        var value: Double
        var location: Int
        var length: Int
    }

    private struct Assignment {
        var marker: Marker
        var value: Double
        var distance: Int
        var afterLabel: Bool
        var numberLocation: Int
    }

    /// Pairs SYS/DIA/PULSE labels with the digits that belong to them.
    ///
    /// Home monitors use two common layouts: the number under a heading
    /// (`SYS` then `128`) and the number above a heading (`128` then `SYS`).
    /// A number between two headings belongs to the heading above it.
    private static func findLabeled(in lines: [RecognizedLine]) -> BloodPressureReading? {
        var assigned: [Marker: Double] = [:]
        var pendingLabel: Marker?
        var pendingNumber: Double?

        for line in lines {
            let markers = markers(in: line.text)
            let numbers = integers(in: line.text).map(\.value).filter { value in
                markers.contains { $0.accepts(value) } || (value >= 30 && value <= 250)
            }
            if markers.isEmpty && numbers.isEmpty { continue }

            if markers.count >= 2 {
                for (marker, value) in assignWithinLine(line.text) where assigned[marker] == nil {
                    assigned[marker] = value
                }
                pendingLabel = nil
                pendingNumber = nil
                continue
            }

            if markers.count == 1, numbers.count == 1, let marker = markers.first, marker.accepts(numbers[0]) {
                if assigned[marker] == nil {
                    assigned[marker] = numbers[0]
                }
                pendingLabel = nil
                pendingNumber = nil
                continue
            }

            if let marker = markers.first, numbers.isEmpty {
                if let number = pendingNumber, marker.accepts(number), assigned[marker] == nil {
                    assigned[marker] = number
                    pendingNumber = nil
                }
                pendingLabel = marker
                continue
            }

            if let number = numbers.first, markers.isEmpty {
                if let label = pendingLabel, label.accepts(number), assigned[label] == nil {
                    assigned[label] = number
                    pendingLabel = nil
                } else {
                    pendingNumber = number
                    pendingLabel = nil
                }
            }
        }

        guard let systolic = assigned[.systolic],
              let diastolic = assigned[.diastolic],
              isPlausible(systolic: systolic, diastolic: diastolic) else {
            return nil
        }
        let pulse = assigned[.pulse].flatMap { isPulse($0, systolic: systolic, diastolic: diastolic) ? $0 : nil }
        return BloodPressureReading(
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            confidence: 0.86,
            evidence: "SYS \(ReadingFormat.whole(systolic)) DIA \(ReadingFormat.whole(diastolic))"
        )
    }

    private static func markers(in text: String) -> [Marker] {
        Marker.allCases.filter { marker in
            text.range(of: marker.pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func assignWithinLine(_ text: String) -> [Marker: Double] {
        let numbers = integers(in: text)
        let ns = text as NSString
        var candidates: [Assignment] = []
        for marker in Marker.allCases {
            guard let regex = try? NSRegularExpression(pattern: marker.pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                for number in numbers where marker.accepts(number.value) {
                    let labelEnd = match.range.location + match.range.length
                    let numberEnd = number.location + number.length
                    let distance: Int
                    let afterLabel: Bool
                    if number.location >= labelEnd {
                        distance = number.location - labelEnd
                        afterLabel = true
                    } else if numberEnd <= match.range.location {
                        distance = match.range.location - numberEnd
                        afterLabel = false
                    } else {
                        continue
                    }
                    guard distance <= 16 else { continue }
                    candidates.append(Assignment(
                        marker: marker,
                        value: number.value,
                        distance: distance,
                        afterLabel: afterLabel,
                        numberLocation: number.location
                    ))
                }
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.afterLabel != rhs.afterLabel { return lhs.afterLabel && !rhs.afterLabel }
            return lhs.numberLocation < rhs.numberLocation
        }
        var assigned: [Marker: Double] = [:]
        var used = Set<Int>()
        for candidate in candidates {
            if assigned[candidate.marker] != nil || used.contains(candidate.numberLocation) { continue }
            assigned[candidate.marker] = candidate.value
            used.insert(candidate.numberLocation)
        }
        return assigned
    }

    private static func standalonePulse(in text: String, systolic: Double, diastolic: Double) -> Double? {
        let pattern = #"(?i)\b(?:pulse|pul|bpm|hr)\b[^\d]{0,12}(\d{2,3})(?![0-9.])"#
        for groups in DisplayText.captures(in: text, pattern: pattern) {
            guard groups.count > 1, let value = Double(groups[1]), isPulse(value, systolic: systolic, diastolic: diastolic) else { continue }
            return value
        }
        let before = #"(?i)(?<![0-9.])(\d{2,3})[^\d]{0,12}\b(?:pulse|pul|bpm|hr)\b"#
        for groups in DisplayText.captures(in: text, pattern: before) {
            guard groups.count > 1, let value = Double(groups[1]), isPulse(value, systolic: systolic, diastolic: diastolic) else { continue }
            return value
        }
        return nil
    }

    private static func findStack(in lines: [RecognizedLine]) -> BloodPressureReading? {
        var values: [Double] = []
        for line in lines {
            let text = line.text
            guard !DisplayText.containsBloodPressureFraction(text) else { continue }
            for number in integers(in: text) {
                if number.value >= 30 && number.value <= 250 {
                    values.append(number.value)
                }
            }
        }
        guard values.count >= 2 else { return nil }

        for index in 0..<(values.count - 1) {
            let systolic = values[index]
            let diastolic = values[index + 1]
            guard isPlausible(systolic: systolic, diastolic: diastolic) else { continue }
            let used: Set<Int> = [index, index + 1]
            let leftovers = values.enumerated().filter { !used.contains($0.offset) }.map(\.element)
            let pulse: Double?
            if index + 2 < values.count, isPulse(values[index + 2], systolic: systolic, diastolic: diastolic) {
                pulse = values[index + 2]
            } else if leftovers.count == 1, isPulse(leftovers[0], systolic: systolic, diastolic: diastolic) {
                pulse = leftovers[0]
            } else {
                pulse = nil
            }
            return BloodPressureReading(
                systolic: systolic,
                diastolic: diastolic,
                pulse: pulse,
                confidence: 0.58,
                evidence: "\(ReadingFormat.whole(systolic))/\(ReadingFormat.whole(diastolic))"
            )
        }
        return nil
    }

    private static func integers(in text: String) -> [IndexedNumber] {
        let pattern = #"(?<![0-9.])(\d{2,3})(?![0-9.])"#
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let range = match.range(at: 1)
            guard range.location != NSNotFound, let value = Double(ns.substring(with: range)) else { return nil }
            return IndexedNumber(value: value, location: range.location, length: range.length)
        }
    }

    private static func isPulse(_ value: Double, systolic: Double, diastolic: Double) -> Bool {
        value >= 30 && value <= 220 && value != systolic && value != diastolic
    }
}
