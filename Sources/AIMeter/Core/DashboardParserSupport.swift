import Foundation

enum DashboardParserSupport {
    static func numericLeaves(from object: Any, path: [String] = []) -> [(path: [String], value: Double)] {
        if let number = object as? NSNumber {
            return [(path, number.doubleValue)]
        }

        if let dictionary = object as? [String: Any] {
            return dictionary.flatMap { key, value in
                numericLeaves(from: value, path: path + [key])
            }
        }

        if let array = object as? [Any] {
            return array.enumerated().flatMap { index, value in
                numericLeaves(from: value, path: path + ["\(index)"])
            }
        }

        return []
    }

    static func jsonLeafStrings(from object: Any) -> [String] {
        if let string = object as? String {
            return [normalizeWhitespace(string)]
        }

        if let dictionary = object as? [String: Any] {
            return dictionary.values.flatMap(jsonLeafStrings(from:))
        }

        if let array = object as? [Any] {
            return array.flatMap(jsonLeafStrings(from:))
        }

        return []
    }

    static func containsAllKeywords(_ path: [String], _ keywords: [String]) -> Bool {
        let lowered = path.map { $0.lowercased() }
        return keywords.allSatisfy { keyword in
            lowered.contains(where: { $0.contains(keyword) })
        }
    }

    static func looksLikePercentPath(_ path: [String]) -> Bool {
        let lowered = path.map { $0.lowercased() }
        return lowered.contains(where: {
            $0.contains("percent") || $0.contains("pct") || $0.contains("ratio") || $0.contains("used")
        })
    }

    static func normalizePercent(_ value: Double) -> Double {
        if value <= 1 {
            return value * 100
        }
        return min(max(value, 0), 100)
    }

    static func stripHTML(from text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    static func normalizedLines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { normalizeWhitespace(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return nil
        }

        let captureRange = match.range(at: 1)
        guard let range = Range(captureRange, in: text) else {
            return nil
        }

        return normalizeWhitespace(String(text[range]))
    }
}
