import Foundation

/// Heuristic reader for home blood pressure cuff LCDs.
///
/// It understands `128/82`, a slash Vision drew as `I` or `|`, SYS/DIA labels
/// (including a header row of labels above a row of digits), side-by-side
/// columns when positions are known, and a plain stack of large digits.
/// Pulse is kept only when a leftover number or a pulse label is present.
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
        if var glued = findGlued(in: ordered) {
            if glued.pulse == nil {
                glued.pulse = standalonePulse(in: text, systolic: glued.systolic, diastolic: glued.diastolic)
                    ?? loneExtraPulse(in: ordered, systolic: glued.systolic, diastolic: glued.diastolic)
            }
            return glued
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
            case .systolic: return #"(?<![A-Za-z])(?:systolic|sys|sbp)(?![A-Za-z])"#
            case .diastolic: return #"(?<![A-Za-z])(?:diastolic|dias|dia|dbp)(?![A-Za-z])"#
            case .pulse: return #"(?<![A-Za-z])(?:pulse|pul|bpm|hr)(?![A-Za-z])"#
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

    private enum Event {
        case label(Marker)
        case number(Double)
    }

    /// Pairs SYS/DIA/PULSE labels with the digits that belong to them.
    ///
    /// Same-line text such as `SYS 128` is paired by character distance.
    /// A row of headings over a row of digits (`SYS DIA PUL` then `128 82 74`)
    /// is zipped in order. When the photo has positions and the numbers sit in
    /// two or more columns, each column is paired on its own so a scrambled
    /// reading order cannot swap the arms.
    private static func findLabeled(in lines: [RecognizedLine]) -> BloodPressureReading? {
        var assigned = assignSameLine(lines)

        if !hasPlausiblePair(assigned), hasLayout(lines) {
            let spatial = assignByColumns(lines)
            if hasPlausiblePair(spatial) {
                let pulse = spatial[.pulse] ?? assigned[.pulse]
                assigned = spatial
                if let pulse {
                    assigned[.pulse] = pulse
                }
            }
        }
        if !hasPlausiblePair(assigned) {
            assigned = merge(assigned, incoming: zipEvents(events(in: lines)))
        }
        return reading(from: assigned, confidence: 0.86)
    }

    private static func assignSameLine(_ lines: [RecognizedLine]) -> [Marker: Double] {
        var assigned: [Marker: Double] = [:]
        for line in lines {
            let lineMarkers = markers(in: line.text)
            let numbers = usableNumbers(in: line.text)
            guard !lineMarkers.isEmpty, !numbers.isEmpty else { continue }
            for (marker, value) in assignWithinLine(line.text) where assigned[marker] == nil {
                assigned[marker] = value
            }
        }
        return assigned
    }

    private static func assignByColumns(_ lines: [RecognizedLine]) -> [Marker: Double] {
        let columns = columns(of: lines)
        guard columns.count >= 2 else { return [:] }
        var assigned: [Marker: Double] = [:]
        for column in columns {
            for (marker, value) in zipEvents(events(in: column)) where assigned[marker] == nil {
                assigned[marker] = value
            }
        }
        return assigned
    }

    private static func events(in lines: [RecognizedLine]) -> [Event] {
        var events: [Event] = []
        for line in lines {
            let lineMarkers = markers(in: line.text)
            let numbers = usableNumbers(in: line.text)
            if !lineMarkers.isEmpty && !numbers.isEmpty { continue }
            if numbers.isEmpty {
                events.append(contentsOf: lineMarkers.map(Event.label))
            } else {
                events.append(contentsOf: numbers.map(Event.number))
            }
        }
        return events
    }

    private static func zipEvents(_ events: [Event]) -> [Marker: Double] {
        var assigned: [Marker: Double] = [:]
        var index = 0
        while index < events.count {
            let start = index
            switch events[index] {
            case .label:
                var labels: [Marker] = []
                while index < events.count, case .label(let marker) = events[index] {
                    labels.append(marker)
                    index += 1
                }
                var numbers: [Double] = []
                while index < events.count, case .number(let value) = events[index] {
                    numbers.append(value)
                    index += 1
                }
                if !numbers.isEmpty {
                    zip(labels: labels, numbers: numbers, into: &assigned)
                }
            case .number:
                var numbers: [Double] = []
                while index < events.count, case .number(let value) = events[index] {
                    numbers.append(value)
                    index += 1
                }
                var labels: [Marker] = []
                while index < events.count, case .label(let marker) = events[index] {
                    labels.append(marker)
                    index += 1
                }
                if !labels.isEmpty {
                    zip(labels: labels, numbers: numbers, into: &assigned)
                }
            }
            if index == start { index += 1 }
        }
        return assigned
    }

    private static func zip(labels: [Marker], numbers: [Double], into assigned: inout [Marker: Double]) {
        let count = min(labels.count, numbers.count)
        for offset in 0..<count {
            let marker = labels[offset]
            let value = numbers[offset]
            guard assigned[marker] == nil, marker.accepts(value) else { continue }
            assigned[marker] = value
        }
        guard assigned[.pulse] == nil, numbers.count > count,
              labels.contains(.systolic), labels.contains(.diastolic),
              let systolic = assigned[.systolic], let diastolic = assigned[.diastolic] else { return }
        let extra = numbers[count]
        if isPulse(extra, systolic: systolic, diastolic: diastolic) {
            assigned[.pulse] = extra
        }
    }

    private static func merge(_ existing: [Marker: Double], incoming: [Marker: Double]) -> [Marker: Double] {
        var merged = existing
        for (marker, value) in incoming where merged[marker] == nil {
            merged[marker] = value
        }
        return merged
    }

    private static func hasPlausiblePair(_ assigned: [Marker: Double]) -> Bool {
        guard let systolic = assigned[.systolic], let diastolic = assigned[.diastolic] else { return false }
        return isPlausible(systolic: systolic, diastolic: diastolic)
    }

    private static func reading(from assigned: [Marker: Double], confidence: Double) -> BloodPressureReading? {
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
            confidence: confidence,
            evidence: "SYS \(ReadingFormat.whole(systolic)) DIA \(ReadingFormat.whole(diastolic))"
        )
    }

    private static func hasLayout(_ lines: [RecognizedLine]) -> Bool {
        lines.contains { $0.width > 0.02 || $0.height > 0.02 }
    }

    private static func columns(of lines: [RecognizedLine]) -> [[RecognizedLine]] {
        let sorted = lines.sorted { centerX($0) < centerX($1) }
        var groups: [[RecognizedLine]] = []
        var anchors: [Double] = []
        for line in sorted {
            let x = centerX(line)
            if let index = anchors.indices.min(by: { abs(anchors[$0] - x) < abs(anchors[$1] - x) }),
               abs(anchors[index] - x) <= 0.16 {
                groups[index].append(line)
                let count = Double(groups[index].count)
                anchors[index] += (x - anchors[index]) / count
            } else {
                groups.append([line])
                anchors.append(x)
            }
        }
        return groups.map { column in
            column.sorted { lhs, rhs in
                if abs(lhs.top - rhs.top) > 0.012 { return lhs.top > rhs.top }
                return lhs.x < rhs.x
            }
        }
    }

    private static func centerX(_ line: RecognizedLine) -> Double {
        line.x + line.width / 2
    }

    private static func markers(in text: String) -> [Marker] {
        let ns = text as NSString
        var found: [(Marker, Int)] = []
        for marker in Marker.allCases {
            guard let regex = try? NSRegularExpression(pattern: marker.pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                found.append((marker, match.range.location))
            }
        }
        return found.sorted { $0.1 < $1.1 }.map(\.0)
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
                    guard distance <= 24 else { continue }
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
        let pattern = #"(?i)(?<![A-Za-z])(?:pulse|pul|bpm|hr)(?![A-Za-z])[^\d]{0,12}(\d{2,3})(?![0-9.])"#
        for groups in DisplayText.captures(in: text, pattern: pattern) {
            guard groups.count > 1, let value = Double(groups[1]), isPulse(value, systolic: systolic, diastolic: diastolic) else { continue }
            return value
        }
        let before = #"(?i)(?<![0-9.])(\d{2,3})[^\d]{0,12}(?<![A-Za-z])(?:pulse|pul|bpm|hr)(?![A-Za-z])"#
        for groups in DisplayText.captures(in: text, pattern: before) {
            guard groups.count > 1, let value = Double(groups[1]), isPulse(value, systolic: systolic, diastolic: diastolic) else { continue }
            return value
        }
        return nil
    }

    /// Five to seven digits with no slash, as in `12882` or `1288274`.
    /// Sentences are ignored so a serial number inside a paragraph is not a reading.
    private static func findGlued(in lines: [RecognizedLine]) -> BloodPressureReading? {
        guard !isSentence(lines) else { return nil }
        let text = lines.map(\.text).joined(separator: "\n")
        let pattern = #"(?<![0-9.])(\d{5,7})(?![0-9.])"#
        for groups in DisplayText.captures(in: text, pattern: pattern) {
            guard groups.count > 1, let reading = splitGlued(groups[1]) else { continue }
            return reading
        }
        return nil
    }

    private static func splitGlued(_ digits: String) -> BloodPressureReading? {
        let splits: [(sys: Int, dia: Int, pulse: Int?)]
        switch digits.count {
        case 5:
            splits = [(3, 2, nil), (2, 3, nil)]
        case 6:
            splits = [(3, 3, nil)]
        case 7:
            splits = [(3, 2, 2)]
        default:
            return nil
        }
        for split in splits {
            guard let pair = slice(digits, sys: split.sys, dia: split.dia, pulse: split.pulse) else { continue }
            return pair
        }
        return nil
    }

    private static func slice(_ digits: String, sys: Int, dia: Int, pulse pulseLength: Int?) -> BloodPressureReading? {
        let sysEnd = digits.index(digits.startIndex, offsetBy: sys)
        let diaEnd = digits.index(sysEnd, offsetBy: dia)
        guard let systolic = Double(digits[..<sysEnd]),
              let diastolic = Double(digits[sysEnd..<diaEnd]),
              isPlausible(systolic: systolic, diastolic: diastolic) else { return nil }
        var pulse: Double?
        if let pulseLength {
            let pulseEnd = digits.index(diaEnd, offsetBy: pulseLength)
            guard let value = Double(digits[diaEnd..<pulseEnd]),
                  isPulse(value, systolic: systolic, diastolic: diastolic) else { return nil }
            pulse = value
        }
        return BloodPressureReading(
            systolic: systolic,
            diastolic: diastolic,
            pulse: pulse,
            confidence: pulse == nil ? 0.66 : 0.68,
            evidence: "\(ReadingFormat.whole(systolic))/\(ReadingFormat.whole(diastolic))"
        )
    }

    private static func loneExtraPulse(in lines: [RecognizedLine], systolic: Double, diastolic: Double) -> Double? {
        let extras = lines.flatMap { usableNumbers(in: $0.text) }.filter { $0 != systolic && $0 != diastolic }
        guard extras.count == 1, isPulse(extras[0], systolic: systolic, diastolic: diastolic) else { return nil }
        return extras[0]
    }

    private struct StackedNumber {
        var value: Double
        var height: Double
        var top: Double
        var x: Double
    }

    private static func findStack(in lines: [RecognizedLine]) -> BloodPressureReading? {
        guard !isSentence(lines) else { return nil }
        var numbers: [StackedNumber] = []
        for line in lines {
            guard !DisplayText.containsBloodPressureFraction(line.text) else { continue }
            for number in integers(in: line.text) where number.value >= 30 && number.value <= 250 {
                numbers.append(StackedNumber(value: number.value, height: line.height, top: line.top, x: line.x))
            }
        }
        guard numbers.count >= 2 else { return nil }
        let prominent = prominentNumbers(numbers)
        let pool: [StackedNumber]
        if prominent.count >= 2, prominent.count < numbers.count {
            pool = prominent
        } else if numbers.count <= 6 || lines.contains(where: { DisplayText.containsMillimetersOfMercury($0.text) }) {
            pool = numbers
        } else {
            return nil
        }
        return stackReading(from: pool)
    }

    /// Prefer the tall LCD digits when the photo also contains small memory or clock debris.
    private static func prominentNumbers(_ numbers: [StackedNumber]) -> [StackedNumber] {
        let maxHeight = numbers.map(\.height).max() ?? 0
        guard maxHeight > 0.02 else { return [] }
        let tall = numbers.filter { $0.height >= maxHeight * 0.45 }
        guard tall.count >= 2 else { return [] }
        return tall.sorted { lhs, rhs in
            if abs(lhs.top - rhs.top) > 0.012 { return lhs.top > rhs.top }
            return lhs.x < rhs.x
        }
    }

    private static func stackReading(from values: [StackedNumber]) -> BloodPressureReading? {
        guard values.count >= 2 else { return nil }
        for index in 0..<(values.count - 1) {
            let systolic = values[index].value
            let diastolic = values[index + 1].value
            guard isPlausible(systolic: systolic, diastolic: diastolic) else { continue }
            let used: Set<Int> = [index, index + 1]
            let leftovers = values.enumerated().filter { !used.contains($0.offset) }.map(\.element.value)
            let pulse: Double?
            if index + 2 < values.count, isPulse(values[index + 2].value, systolic: systolic, diastolic: diastolic) {
                pulse = values[index + 2].value
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

    /// A paragraph that happens to contain two plausible numbers is not a cuff.
    private static func isSentence(_ lines: [RecognizedLine]) -> Bool {
        let text = lines.map(\.text).joined(separator: " ")
        let stripped = DisplayText.replacing(
            text,
            pattern: #"(?i)\b(?:systolic|diastolic|pulse|sys|dia|pul|sbp|dbp|bpm|hr|mmhg|min)\b"#,
            with: " "
        )
        let letters = stripped.filter(\.isLetter).count
        let digits = stripped.filter(\.isNumber).count
        return letters >= 24 && letters > digits * 3
    }

    private static func usableNumbers(in text: String) -> [Double] {
        integers(in: text).map(\.value).filter { $0 >= 30 && $0 <= 250 }
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
