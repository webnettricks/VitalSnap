import Foundation

enum DisplayText {
    struct FoundNumber: Equatable {
        var value: Double
        var raw: String
    }

    static func normalize(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        text = String(text.map { fullwidthFold[$0] ?? $0 })
        text = text.replacingOccurrences(of: "／", with: "/")
        text = text.replacingOccurrences(of: "∕", with: "/")
        text = text.replacingOccurrences(of: "•", with: "/")
        text = text.replacingOccurrences(of: "·", with: "/")
        // Unit words before digit repair, so "1b" stays "lb" instead of becoming 18.
        text = replacing(text, pattern: #"(?i)\b1bs\b"#, with: "lbs")
        text = replacing(text, pattern: #"(?i)\bibs\b"#, with: "lbs")
        text = replacing(text, pattern: #"(?i)\b1b\b"#, with: "lb")
        text = replacing(text, pattern: #"(?i)\blb5\b"#, with: "lbs")
        text = replacing(text, pattern: #"(?i)\bk9\b"#, with: "kg")
        text = replacing(text, pattern: #"(?i)\bkq\b"#, with: "kg")
        // Labels before digit repair, so "D1A" stays DIA instead of becoming 01A.
        text = repairBloodPressureLabels(text)
        text = replacing(text, pattern: #"(?<=\d{2})\s*[Il|]\s*(?=\d{2})"#, with: "/")
        text = replacing(text, pattern: #"(?<=\d)[.,]0+(?!\d)"#, with: "")
        text = replacing(text, pattern: #"(?<=\d)[.,]+(?!\d)"#, with: "")

        let pieces = text.split(whereSeparator: \.isWhitespace).map { repairToken(String($0)) }
        return pieces.joined(separator: " ")
    }

    static func numbers(in text: String) -> [FoundNumber] {
        let pattern = #"(?<![A-Za-z0-9])(\d{1,3}(?:[.,]\d{1,2})?)(?![A-Za-z0-9])"#
        return captures(in: text, pattern: pattern).compactMap { groups in
            guard groups.count > 1, let value = parseDecimal(groups[1]) else { return nil }
            return FoundNumber(value: value, raw: groups[1])
        }
    }

    static func parseDecimal(_ raw: String) -> Double? {
        var token = raw
        if token.contains(","), !token.contains(".") {
            let fraction = token.split(separator: ",").last.map(String.init) ?? ""
            if fraction.count <= 2 {
                token = token.replacingOccurrences(of: ",", with: ".")
            } else {
                token = token.replacingOccurrences(of: ",", with: "")
            }
        }
        return Double(token)
    }

    static func massUnit(in text: String) -> MassUnit? {
        let units = massUnitMentions(in: text)
        return units.first?.unit
    }

    struct UnitMention {
        var unit: MassUnit
        var location: Int
        var length: Int
    }

    static func massUnitMentions(in text: String) -> [UnitMention] {
        let pattern = #"(?i)\b(?:kilograms?|kgs?|pounds?|lbs?)\b"#
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, range: range).compactMap { match in
            let word = ns.substring(with: match.range).lowercased()
            let unit: MassUnit = (word.hasPrefix("k") ? .kilograms : .pounds)
            return UnitMention(unit: unit, location: match.range.location, length: match.range.length)
        }
    }

    static func isDistractor(_ text: String) -> Bool {
        let patterns = [
            #"\b\d{1,2}:\d{2}\b"#,
            #"\bbmi\b"#,
            #"\bfat\b"#,
            #"\bmuscle\b"#,
            #"\bbone\b"#,
            #"\bwater\b"#,
            #"\bvisceral\b"#,
            #"\bkcal\b"#,
            #"\bcalories?\b"#,
            #"\bheight\b"#,
            #"\bage\b"#,
            #"\bbmr\b"#,
            #"\bamr\b"#,
            #"\bcm\b"#,
            "%",
        ]
        return patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    static func containsBloodPressureFraction(_ text: String) -> Bool {
        text.range(of: #"(?<![0-9.])\d{2,3}\s*(?:/|over)\s*\d{2,3}(?![0-9.])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func containsMillimetersOfMercury(_ text: String) -> Bool {
        text.range(of: #"mmhg"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    static func captures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).compactMap { index in
                let nsRange = match.range(at: index)
                guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: text) else { return nil }
                return String(text[swiftRange])
            }
        }
    }

    /// Seven-segment LCDs share shapes with a handful of letters. Only tokens that
    /// already contain a digit are rewritten, and only when every other character
    /// is one of those shapes, so words such as SYS are left alone.
    private static let digitLookalikes: [Character: Character] = [
        "O": "0", "o": "0", "Q": "0", "D": "0", "Ø": "0",
        "I": "1", "l": "1", "|": "1",
        "Z": "2", "z": "2",
        "S": "5", "s": "5",
        "G": "6", "b": "6",
        "B": "8",
        "g": "9", "q": "9",
    ]

    private static func repairBloodPressureLabels(_ text: String) -> String {
        var text = text
        text = replacing(text, pattern: #"(?i)(?<![A-Za-z])[s5][y¥][s5](?![A-Za-z])"#, with: "SYS")
        text = replacing(text, pattern: #"(?i)(?<![A-Za-z])d[i1l|]a(?:stolic)?(?![A-Za-z])"#, with: "DIA")
        text = replacing(text, pattern: #"(?i)(?<![A-Za-z])d[i1l|]as(?![A-Za-z])"#, with: "DIA")
        text = replacing(text, pattern: #"(?i)(?<![A-Za-z])p[uµ][l1|][s5]e(?![A-Za-z])"#, with: "PULSE")
        text = replacing(text, pattern: #"(?i)(?<![A-Za-z])p[uµ][l1|](?![A-Za-z])"#, with: "PUL")
        text = replacing(text, pattern: #"(?i)(?<![A-Za-z])mm\s*h[gq9](?![A-Za-z])"#, with: "mmHg")
        return text
    }

    private static func repairToken(_ token: String) -> String {
        guard token.contains(where: \.isNumber) else { return token }
        guard token.allSatisfy(isRepairCharacter) else { return token }
        let chars = Array(token)
        var repaired = ""
        for (index, character) in chars.enumerated() {
            if isSlashLookalike(character), separatesDigitRuns(chars, at: index) {
                repaired.append("/")
            } else if let mapped = digitLookalikes[character] {
                repaired.append(mapped)
            } else {
                repaired.append(character)
            }
        }
        var candidate = repaired
        while candidate.count > 1, let last = candidate.last, last == "," || last == "." {
            if isNumericToken(candidate) { break }
            candidate.removeLast()
        }
        guard isNumericToken(candidate) else { return token }
        return candidate
    }

    private static func isRepairCharacter(_ character: Character) -> Bool {
        character.isNumber
            || character == "."
            || character == ","
            || character == "/"
            || digitLookalikes[character] != nil
    }

    private static func isSlashLookalike(_ character: Character) -> Bool {
        character == "I" || character == "l" || character == "|"
    }

    /// A single I, l, or bar between two 2–3 digit runs is the slash Vision missed.
    /// A lookalike sitting inside one number, as in "1I8", stays a digit.
    private static func separatesDigitRuns(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0, index < chars.count - 1 else { return false }
        let left = digitRunLength(chars, from: index - 1, step: -1)
        let right = digitRunLength(chars, from: index + 1, step: 1)
        return (2...3).contains(left) && (2...3).contains(right)
    }

    private static func digitRunLength(_ chars: [Character], from start: Int, step: Int) -> Int {
        var index = start
        var count = 0
        while index >= 0, index < chars.count, isDigitSide(chars[index]) {
            count += 1
            index += step
        }
        return count
    }

    private static func isDigitSide(_ character: Character) -> Bool {
        character.isNumber || (digitLookalikes[character] != nil && !isSlashLookalike(character))
    }

    private static func isNumericToken(_ text: String) -> Bool {
        text.range(
            of: #"^\d{1,4}(?:[.,]\d{1,2})?(?:/\d{1,4}(?:[.,]\d{1,2})?){0,2}$"#,
            options: .regularExpression
        ) != nil
    }

    private static let fullwidthFold: [Character: Character] = [
        "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
        "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
        "．": ".", "，": ",",
    ]
}
