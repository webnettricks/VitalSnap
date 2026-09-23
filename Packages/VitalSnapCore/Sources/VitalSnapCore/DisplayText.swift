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
        text = replacing(text, pattern: #"(?i)\b1bs\b"#, with: "lbs")
        text = replacing(text, pattern: #"(?i)\bibs\b"#, with: "lbs")
        text = replacing(text, pattern: #"(?i)\b1b\b"#, with: "lb")
        text = replacing(text, pattern: #"(?i)\blb5\b"#, with: "lbs")
        text = replacing(text, pattern: #"(?i)\bk9\b"#, with: "kg")
        text = replacing(text, pattern: #"(?i)\bkq\b"#, with: "kg")

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

    private static func repairToken(_ token: String) -> String {
        let digits = token.filter(\.isNumber)
        guard !digits.isEmpty else { return token }
        let letters = token.filter(\.isLetter)
        guard !letters.isEmpty, letters.allSatisfy({ "OoIl".contains($0) }) else { return token }
        return String(token.map { character in
            switch character {
            case "O", "o": return "0"
            case "I", "l": return "1"
            default: return character
            }
        })
    }

    private static let fullwidthFold: [Character: Character] = [
        "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
        "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
        "．": ".", "，": ",",
    ]
}
