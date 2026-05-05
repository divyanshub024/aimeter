import Foundation

enum CursorDashboardParser {
    enum ParseResult: Equatable {
        case usage(CursorUsageSnapshot)
        case authRequired
        case noMatch
    }

    static func parseResponseBody(_ body: String, sourceURL: String) -> ParseResult {
        guard CursorURLValidator.isAllowedCursorURLString(sourceURL) else {
            return .noMatch
        }

        return parseResponseBody(body, sourceURL: sourceURL, allowAuthDetection: false)
    }

    static func parseDOMText(_ text: String, sourceURL: String) -> ParseResult {
        parseText(text, sourceURL: sourceURL, allowAuthDetection: true)
    }

    private static func parseResponseBody(_ body: String, sourceURL: String, allowAuthDetection: Bool) -> ParseResult {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBody.isEmpty {
            return .noMatch
        }

        if let data = trimmedBody.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data)
        {
            if let snapshot = parseJSONObject(jsonObject) {
                return .usage(snapshot)
            }

            let text = DashboardParserSupport.jsonLeafStrings(from: jsonObject).joined(separator: " ")
            let textResult = parseText(text, sourceURL: sourceURL, allowAuthDetection: allowAuthDetection)
            if textResult != .noMatch {
                return textResult
            }
        }

        return parseText(
            DashboardParserSupport.stripHTML(from: trimmedBody),
            sourceURL: sourceURL,
            allowAuthDetection: allowAuthDetection
        )
    }

    private static func parseJSONObject(_ object: Any) -> CursorUsageSnapshot? {
        let leaves = DashboardParserSupport.numericLeaves(from: object)
        guard !leaves.isEmpty else {
            return nil
        }

        let total = bestPercent(
            in: leaves,
            preferredKeys: [["total"], ["overall"], ["aggregate"]]
        )

        let auto = bestPercent(
            in: leaves,
            preferredKeys: [["auto"]]
        )

        let api = bestPercent(
            in: leaves,
            preferredKeys: [["api"]]
        )

        guard let total, let auto, let api else {
            return nil
        }

        let planLabel = DashboardParserSupport.jsonLeafStrings(from: object)
            .first(where: isPlanLabel) ?? "Cursor Plan"

        return CursorUsageSnapshot(
            planLabel: planLabel,
            totalUsedPercent: total,
            autoUsedPercent: auto,
            apiUsedPercent: api,
            fetchedAt: Date(),
            connectionState: .connected
        )
    }

    private static func bestPercent(
        in leaves: [(path: [String], value: Double)],
        preferredKeys: [[String]]
    ) -> Double? {
        for preferred in preferredKeys {
            if let match = leaves.first(where: {
                DashboardParserSupport.containsAllKeywords($0.path, preferred)
                    && DashboardParserSupport.looksLikePercentPath($0.path)
            }) {
                return DashboardParserSupport.normalizePercent(match.value)
            }
        }

        for preferred in preferredKeys {
            if let match = leaves.first(where: {
                DashboardParserSupport.containsAllKeywords($0.path, preferred)
            }) {
                return DashboardParserSupport.normalizePercent(match.value)
            }
        }

        return nil
    }

    private static func parseText(_ rawText: String, sourceURL: String, allowAuthDetection: Bool) -> ParseResult {
        let text = DashboardParserSupport.normalizeWhitespace(rawText)
        guard !text.isEmpty else {
            return .noMatch
        }

        if allowAuthDetection && indicatesAuthentication(text: text, sourceURL: sourceURL) {
            return .authRequired
        }

        guard
            let planLabel = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "(Included in\\s+(?:Free|Hobby|Pro\\+?|Ultra(?:\\s+[A-Za-z0-9+]+)?))"
            ),
            let totalPercent = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "Total\\s+(\\d+(?:\\.\\d+)?)%"
            ),
            let autoPercent = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "(\\d+(?:\\.\\d+)?)%\\s+Auto"
            ),
            let apiPercent = DashboardParserSupport.firstMatch(
                in: text,
                pattern: "(\\d+(?:\\.\\d+)?)%\\s+API"
            ),
            let total = Double(totalPercent),
            let auto = Double(autoPercent),
            let api = Double(apiPercent)
        else {
            return .noMatch
        }

        return .usage(
            CursorUsageSnapshot(
                planLabel: planLabel,
                totalUsedPercent: total,
                autoUsedPercent: auto,
                apiUsedPercent: api,
                fetchedAt: Date(),
                connectionState: .connected
            )
        )
    }

    private static func indicatesAuthentication(text: String, sourceURL: String) -> Bool {
        let loweredText = text.lowercased()
        if let url = URL(string: sourceURL) {
            let host = (url.host ?? "").lowercased()
            let path = url.path.lowercased()

            if host.hasPrefix("auth.") {
                return true
            }

            let authPaths = ["/login", "/signin", "/sign-in", "/authorize"]
            if authPaths.contains(where: { path.contains($0) }) {
                return true
            }
        }

        let authPhrases = [
            "sign in to cursor",
            "log in to cursor",
            "continue with google",
            "continue with github",
            "enter your email"
        ]

        return authPhrases.contains(where: loweredText.contains)
    }

    private static func isPlanLabel(_ value: String) -> Bool {
        value.range(
            of: "Included in\\s+(?:Free|Hobby|Pro\\+?|Ultra(?:\\s+[A-Za-z0-9+]+)?)",
            options: .regularExpression
        ) != nil
    }
}
