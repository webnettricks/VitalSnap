import Foundation

enum ReadingOrder {
    /// Top-to-bottom, then left-to-right, using Vision coordinates.
    /// Lines with no position information keep their original order.
    static func sorted(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        let positioned = lines.contains { $0.height > 0 || $0.y > 0 || $0.x > 0 }
        guard positioned else { return lines }
        return lines.enumerated().sorted { lhs, rhs in
            if abs(lhs.element.top - rhs.element.top) > 0.012 {
                return lhs.element.top > rhs.element.top
            }
            if abs(lhs.element.x - rhs.element.x) > 0.012 {
                return lhs.element.x < rhs.element.x
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    static func normalized(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        sorted(lines).map { line in
            var copy = line
            copy.text = DisplayText.normalize(line.text)
            return copy
        }
    }

    static func rawText(_ lines: [RecognizedLine]) -> String {
        normalized(lines)
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
