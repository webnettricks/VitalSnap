import Foundation

/// Heuristic reader for digital bathroom scales.
///
/// It looks for a number next to kg, lb, or stone, and ignores clocks, body-fat
/// percentages, and BMI lines. When the unit is missing it guesses from the
/// magnitude and marks the reading so the person can confirm it.
public enum WeightParser {
    public static func parse(lines: [RecognizedLine]) -> WeightReading? {
        let ordered = ReadingOrder.normalized(lines)
        if let stone = parseStone(in: ordered) {
            return stone
        }

        var candidates: [Candidate] = []
        for (index, line) in ordered.enumerated() where !shouldSkip(line.text) {
            candidates.append(contentsOf: candidatesOnLine(line, index: index, count: ordered.count))
            if let adjacent = adjacentCandidate(around: index, in: ordered) {
                candidates.append(adjacent)
            }
        }

        let inferred = inferredCandidates(in: ordered, existing: candidates)
        candidates.append(contentsOf: inferred)

        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        return WeightReading(
            value: best.value,
            unit: best.unit,
            confidence: confidence(score: best.score, ocr: best.ocr),
            evidence: best.evidence,
            unitWasInferred: best.inferred
        )
    }

    private struct Candidate {
        var value: Double
        var unit: MassUnit
        var score: Double
        var ocr: Double
        var evidence: String
        var inferred: Bool
        var lineIndex: Int
    }

    private static func shouldSkip(_ text: String) -> Bool {
        DisplayText.isDistractor(text)
            || DisplayText.containsBloodPressureFraction(text)
            || DisplayText.containsMillimetersOfMercury(text)
    }

    private static func plausible(_ value: Double, unit: MassUnit) -> Bool {
        switch unit {
        case .kilograms: return value >= 15 && value <= 320
        case .pounds: return value >= 30 && value <= 700
        }
    }

    private static func candidatesOnLine(_ line: RecognizedLine, index: Int, count: Int) -> [Candidate] {
        let mentions = DisplayText.massUnitMentions(in: line.text)
        let numbers = DisplayText.numbers(in: line.text)
        guard !mentions.isEmpty, !numbers.isEmpty else { return [] }

        let ns = line.text as NSString
        return numbers.compactMap { number in
            guard let range = ns.range(of: number.raw).location == NSNotFound ? nil : ns.range(of: number.raw) else {
                return nil
            }
            guard let mention = nearest(mentions, to: range.location) else { return nil }
            guard plausible(number.value, unit: mention.unit) else { return nil }
            let distance = abs(mention.location - range.location)
            var score = 12.0
            score += line.confidence * 2
            score += line.height * 8
            score += decimalBonus(number.raw)
            score += Double(count - index) * 0.05
            score -= min(4, Double(distance) * 0.05)
            return Candidate(
                value: number.value,
                unit: mention.unit,
                score: score,
                ocr: line.confidence,
                evidence: "\(number.raw) \(mention.unit.symbol)",
                inferred: false,
                lineIndex: index
            )
        }
    }

    private static func adjacentCandidate(around index: Int, in lines: [RecognizedLine]) -> Candidate? {
        let line = lines[index]
        guard DisplayText.numbers(in: line.text).isEmpty, let unit = DisplayText.massUnit(in: line.text) else {
            return nil
        }
        let neighbors = [index - 1, index + 1].filter { $0 >= 0 && $0 < lines.count }
        let preferred = neighbors.sorted { lhs, rhs in
            // The digits are usually printed above the unit.
            if lhs == index - 1 { return true }
            if rhs == index - 1 { return false }
            return lhs < rhs
        }
        for neighbor in preferred {
            let source = lines[neighbor]
            if shouldSkip(source.text) || DisplayText.massUnit(in: source.text) != nil {
                continue
            }
            guard let number = DisplayText.numbers(in: source.text).first(where: { plausible($0.value, unit: unit) }) else {
                continue
            }
            var score = 10.0
            score += source.confidence * 2
            score += source.height * 8
            score += decimalBonus(number.raw)
            if neighbor == index - 1 { score += 0.4 }
            return Candidate(
                value: number.value,
                unit: unit,
                score: score,
                ocr: source.confidence,
                evidence: "\(number.raw) \(unit.symbol)",
                inferred: false,
                lineIndex: neighbor
            )
        }
        return nil
    }

    private static func inferredCandidates(in lines: [RecognizedLine], existing: [Candidate]) -> [Candidate] {
        let claimed = Set(existing.map(\.lineIndex))
        var found: [Candidate] = []
        for (index, line) in lines.enumerated() where !claimed.contains(index) && !shouldSkip(line.text) {
            if DisplayText.massUnit(in: line.text) != nil { continue }
            for number in DisplayText.numbers(in: line.text) {
                guard let unit = inferredUnit(for: number.value) else { continue }
                var score = 4.0
                score += line.confidence * 2
                score += line.height * 8
                score += decimalBonus(number.raw)
                score += Double(lines.count - index) * 0.05
                found.append(Candidate(
                    value: number.value,
                    unit: unit,
                    score: score,
                    ocr: line.confidence,
                    evidence: number.raw,
                    inferred: true,
                    lineIndex: index
                ))
            }
        }
        return found
    }

    /// Values at or above 120 are treated as pounds. Lighter readings are treated as kilograms.
    /// Both cases are flagged for confirmation because the ranges overlap.
    private static func inferredUnit(for value: Double) -> MassUnit? {
        if value >= 120, plausible(value, unit: .pounds) { return .pounds }
        if value < 120, plausible(value, unit: .kilograms) { return .kilograms }
        if plausible(value, unit: .pounds) { return .pounds }
        if plausible(value, unit: .kilograms) { return .kilograms }
        return nil
    }

    private static func parseStone(in lines: [RecognizedLine]) -> WeightReading? {
        let pattern = #"(?<![A-Za-z0-9])(\d{1,2})\s*(?:stone|st)\b(?:\s*(\d{1,2})(?:\s*(?:lbs?|pounds?))?)?"#
        for line in lines where !DisplayText.isDistractor(line.text) {
            guard let groups = DisplayText.captures(in: line.text, pattern: pattern).first,
                  groups.count > 1,
                  let stones = Double(groups[1]),
                  stones >= 3, stones <= 45 else { continue }
            let extraPounds = groups.count > 2 ? (Double(groups[2]) ?? 0) : 0
            guard extraPounds >= 0, extraPounds < 14 else { continue }
            let pounds = stones * 14 + extraPounds
            guard plausible(pounds, unit: .pounds) else { continue }
            let evidence = groups[0]
            return WeightReading(
                value: pounds,
                unit: .pounds,
                confidence: min(1, 0.8 + line.confidence * 0.15),
                evidence: evidence,
                unitWasInferred: false
            )
        }
        return nil
    }

    private static func decimalBonus(_ raw: String) -> Double {
        let separator: Character = raw.contains(",") && !raw.contains(".") ? "," : "."
        guard let dot = raw.firstIndex(of: separator) else { return 0 }
        let fraction = raw[raw.index(after: dot)...]
        return fraction.count == 1 ? 0.5 : 0.2
    }

    private static func nearest(_ mentions: [DisplayText.UnitMention], to location: Int) -> DisplayText.UnitMention? {
        mentions.min { abs($0.location - location) < abs($1.location - location) }
    }

    private static func confidence(score: Double, ocr: Double) -> Double {
        let normalized = min(1, max(0, score / 16))
        return min(1, normalized * (0.5 + 0.5 * min(1, max(0, ocr))))
    }
}
