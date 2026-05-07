import Foundation

enum ClaudeDashboardParser {
    private static let maximumStatusLineLength = 140

    enum ParseResult: Equatable {
        case usage(ProviderUsageSnapshot)
        case authRequired
        case noMatch
    }

    static func parseDOMText(_ text: String, sourceURL: String) -> ParseResult {
        parseText(text, sourceURL: sourceURL, allowAuthDetection: true)
    }

    static func parseResponseBody(_ body: String, sourceURL: String) -> ParseResult {
        guard ClaudeURLValidator.isAllowedClaudeURLString(sourceURL) else {
            return .noMatch
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            return .noMatch
        }

        if
            let data = trimmedBody.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data)
        {
            let leafText = DashboardParserSupport.jsonLeafStrings(from: object).joined(separator: "\n")
            return parseText(
                leafText,
                sourceURL: sourceURL,
                allowAuthDetection: false,
                requireUsagePercent: true
            )
        }

        return parseText(
            DashboardParserSupport.stripHTML(from: trimmedBody),
            sourceURL: sourceURL,
            allowAuthDetection: false,
            requireUsagePercent: true
        )
    }

    private static func parseText(
        _ text: String,
        sourceURL: String,
        allowAuthDetection: Bool,
        requireUsagePercent: Bool = false
    ) -> ParseResult {
        guard ClaudeURLValidator.isAllowedClaudeURLString(sourceURL) else {
            return .noMatch
        }

        let normalized = DashboardParserSupport.normalizeWhitespace(text)
        guard !normalized.isEmpty else {
            return .noMatch
        }

        if allowAuthDetection && looksLikeAuthPage(normalized) {
            return .authRequired
        }

        if
            allowAuthDetection,
            !ClaudeURLValidator.isUsageSettingsURLString(sourceURL),
            let signedInSnapshot = signedInAppSnapshot(from: normalized)
        {
            return .usage(signedInSnapshot)
        }

        return parseUsageText(text, sourceURL: sourceURL, requireUsagePercent: requireUsagePercent)
    }

    private static func parseUsageText(_ text: String, sourceURL: String, requireUsagePercent: Bool) -> ParseResult {
        let lines = DashboardParserSupport.normalizedLines(from: text)
        let lowercased = text.lowercased()

        guard lowercased.contains("claude") || lowercased.contains("usage") || lowercased.contains("limit") else {
            return .noMatch
        }

        let planLabel = planLabel(from: lines)
        let usageMetrics = usageMetrics(from: lines, sourceURL: sourceURL)
        let primaryUsageMetric = usageMetrics.first
        let usagePercent = primaryUsageMetric?.percent ?? usagePercent(from: text)
        let limitLine = firstLimitLine(from: lines)
        let resetLine = firstResetLine(from: lines)

        guard usagePercent != nil || limitLine != nil || resetLine != nil else {
            return .noMatch
        }

        if requireUsagePercent && usagePercent == nil {
            return .noMatch
        }

        let primaryMetric: UsageMetric
        if let primaryUsageMetric {
            primaryMetric = primaryUsageMetric
        } else if let usagePercent {
            primaryMetric = UsageMetric(
                title: "Usage",
                value: DisplayFormatting.percent(usagePercent),
                percent: usagePercent
            )
        } else if let resetLine {
            primaryMetric = UsageMetric(title: "Limit", value: resetLine)
        } else if let limitLine {
            primaryMetric = UsageMetric(title: "Limit", value: limitLine)
        } else {
            primaryMetric = UsageMetric(title: "Usage", value: "Available")
        }

        let statusMetrics = [limitLine, resetLine]
            .compactMap { $0 }
            .removingDuplicates()
            .filter { line in
                line != primaryMetric.value &&
                    !usageMetrics.contains { metric in metric.value == line }
            }
            .map { line in
                UsageMetric(title: metricTitle(for: line), value: line)
            }
        let secondaryMetrics = (Array(usageMetrics.dropFirst()) + statusMetrics)
            .removingDuplicateMetrics()

        return .usage(
            ProviderUsageSnapshot(
                provider: .claude,
                planLabel: planLabel,
                primaryMetric: primaryMetric,
                secondaryMetrics: secondaryMetrics,
                fetchedAt: Date(),
                connectionState: .connected
            )
        )
    }

    private static func usagePercent(from text: String) -> Double? {
        if let used = percent(in: text, pattern: #"(?i)(?:usage|used|limit)[^%\n]{0,80}?(\d{1,3}(?:\.\d+)?)\s*%"#) {
            return used
        }

        if let remaining = percent(in: text, pattern: #"(?i)(\d{1,3}(?:\.\d+)?)\s*%\s*(?:remaining|left)"#) {
            return 100 - remaining
        }

        return nil
    }

    private static func usageMetrics(from lines: [String], sourceURL: String) -> [UsageMetric] {
        var metrics: [UsageMetric] = []
        var percentLineIndex = 0

        for (index, line) in lines.enumerated() {
            guard let percent = percentUsed(in: line, at: index, lines: lines, sourceURL: sourceURL) else {
                continue
            }

            let detectedTitle = titleForUsageMetric(before: index, in: lines)
            guard let title = normalizedUsageMetricTitle(
                detectedTitle,
                percentLineIndex: percentLineIndex,
                sourceURL: sourceURL
            ) else {
                percentLineIndex += 1
                continue
            }
            percentLineIndex += 1
            let resetLine = resetLineForUsageMetric(near: index, in: lines)
            metrics.append(
                UsageMetric(
                    title: title,
                    value: DisplayFormatting.percent(percent),
                    percent: percent
                )
            )
            if let resetLine {
                metrics.append(UsageMetric(title: resetMetricTitle(for: title), value: resetLine))
            }
        }

        return metrics
            .normalizedUsageSettingsMetrics(sourceURL: sourceURL)
    }

    private static func normalizedUsageMetricTitle(
        _ title: String,
        percentLineIndex: Int,
        sourceURL: String
    ) -> String? {
        guard title.localizedCaseInsensitiveCompare("Extra usage") != .orderedSame else {
            return nil
        }

        guard ClaudeURLValidator.isUsageSettingsURLString(sourceURL) else {
            return title
        }

        if knownUsageMetricTitle(from: title) != nil {
            return title
        }

        let fallbackTitles = [
            "Current session",
            "All models",
            "Claude Design"
        ]

        guard fallbackTitles.indices.contains(percentLineIndex) else {
            return nil
        }

        return fallbackTitles[percentLineIndex]
    }

    private static func percentUsed(
        in line: String,
        at index: Int,
        lines: [String],
        sourceURL: String
    ) -> Double? {
        if let value = DashboardParserSupport.firstMatch(
            in: line,
            pattern: #"(?i)(\d{1,3}(?:\.\d+)?)\s*%\s*(?:used|usage)"#
        ) {
            return Double(value).map { min(max($0, 0), 100) }
        }

        guard ClaudeURLValidator.isUsageSettingsURLString(sourceURL) else {
            return nil
        }

        guard let bareValue = DashboardParserSupport.firstMatch(
            in: line,
            pattern: #"^\s*(\d{1,3}(?:\.\d+)?)\s*%\s*$"#
        ) else {
            return nil
        }

        guard isNearUsageMetricContext(index: index, in: lines) else {
            return nil
        }

        return Double(bareValue).map { min(max($0, 0), 100) }
    }

    private static func titleForUsageMetric(before index: Int, in lines: [String]) -> String {
        guard index > 0 else {
            return "Usage"
        }

        let lowerBound = max(0, index - 12)
        for candidateIndex in stride(from: index - 1, through: lowerBound, by: -1) {
            if let knownTitle = knownUsageMetricTitle(from: lines[candidateIndex]) {
                return knownTitle
            }
        }

        for candidateIndex in stride(from: index - 1, through: lowerBound, by: -1) {
            let line = lines[candidateIndex]
            let lowercased = line.lowercased()
            if lowercased.contains("reset")
                || lowercased.contains("learn more")
                || lowercased.contains("consume")
                || lowercased.contains("usage limits faster")
                || lowercased.contains("plan usage limits")
                || lowercased.contains("weekly limits")
                || lowercased.contains("additional features")
                || lowercased.contains("extra usage")
                || lowercased.contains("$0.00 spent")
                || isPlanOnlyLine(lowercased)
                || lowercased.contains("%")
                || line.count > 60
            {
                continue
            }

            return line
        }

        return "Usage"
    }

    private static func resetLineForUsageMetric(near index: Int, in lines: [String]) -> String? {
        let lowerBound = max(0, index - 6)
        let upperBound = min(lines.count - 1, index + 4)

        if let line = resetLine(in: lines, from: index - 1, through: lowerBound, by: -1) {
            return line
        }

        return resetLine(in: lines, from: index + 1, through: upperBound, by: 1)
    }

    private static func resetLine(
        in lines: [String],
        from startIndex: Int,
        through endIndex: Int,
        by strideValue: Int
    ) -> String? {
        guard lines.indices.contains(startIndex), lines.indices.contains(endIndex) else {
            return nil
        }

        for candidateIndex in stride(from: startIndex, through: endIndex, by: strideValue) {
            let line = lines[candidateIndex]
            guard isReasonableStatusLine(line) else {
                continue
            }

            let lowercased = line.lowercased()
            if lowercased.contains("reset") || lowercased.contains("resets") {
                return line
            }
        }

        return nil
    }

    private static func isNearUsageMetricContext(index: Int, in lines: [String]) -> Bool {
        let lowerBound = max(0, index - 6)
        let upperBound = min(lines.count - 1, index + 3)

        for candidateIndex in lowerBound...upperBound where candidateIndex != index {
            let line = lines[candidateIndex]
            let lowercased = line.lowercased()
            if knownUsageMetricTitle(from: line) != nil
                || lowercased.contains("used")
                || lowercased.contains("usage")
                || lowercased.contains("reset")
                || lowercased.contains("resets")
            {
                return true
            }
        }

        return false
    }

    private static func resetMetricTitle(for usageTitle: String) -> String {
        usageTitle.localizedCaseInsensitiveCompare("Current session") == .orderedSame
            ? "Reset"
            : "\(usageTitle) reset"
    }

    private static func knownUsageMetricTitle(from line: String) -> String? {
        let normalized = DashboardParserSupport.normalizeWhitespace(line)
        let lowercased = normalized.lowercased()

        guard !lowercased.contains("consume"), !lowercased.contains("usage limits faster") else {
            return nil
        }

        if lowercased == "current session" {
            return "Current session"
        }
        if lowercased == "all models" {
            return "All models"
        }
        if lowercased == "claude design" {
            return "Claude Design"
        }
        if lowercased == "daily included routine runs" {
            return "Daily routines"
        }
        if lowercased.hasPrefix("opus ") || lowercased == "opus" {
            return "Opus"
        }

        return nil
    }

    private static func isPlanOnlyLine(_ lowercasedLine: String) -> Bool {
        ["free", "pro", "max", "team", "enterprise"].contains(lowercasedLine)
    }

    fileprivate static func metricPriority(_ title: String) -> Int {
        let lowercased = title.lowercased()
        if lowercased.contains("current session") {
            return 0
        }
        if lowercased.contains("all models") {
            return 1
        }
        if lowercased.contains("opus") {
            return 2
        }
        if lowercased.contains("claude design") {
            return 3
        }
        return 10
    }

    private static func percent(in text: String, pattern: String) -> Double? {
        guard let match = DashboardParserSupport.firstMatch(in: text, pattern: pattern) else {
            return nil
        }

        guard let value = Double(match) else {
            return nil
        }

        return min(max(value, 0), 100)
    }

    private static func planLabel(from lines: [String]) -> String {
        let planKeywords = [
            "Claude Max",
            "Claude Pro",
            "Claude Team",
            "Claude Enterprise",
            "Free plan",
            "Pro plan",
            "Max plan",
            "Team plan"
        ]

        for line in lines {
            if let keyword = planKeywords.first(where: { line.localizedCaseInsensitiveContains($0) }) {
                return keyword.hasPrefix("Claude") ? keyword : "Claude \(keyword)"
            }
        }

        for (index, line) in lines.enumerated() {
            guard line.localizedCaseInsensitiveContains("Plan usage limits") else {
                continue
            }

            let nextIndex = lines.index(after: index)
            guard lines.indices.contains(nextIndex) else {
                continue
            }

            switch lines[nextIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "pro":
                return "Claude Pro"
            case "max":
                return "Claude Max"
            case "team":
                return "Claude Team"
            default:
                continue
            }
        }

        return "Claude"
    }

    private static func firstLimitLine(from lines: [String]) -> String? {
        lines.first { line in
            guard isReasonableStatusLine(line) else {
                return false
            }

            let lowercased = line.lowercased()
            guard lowercased != "plan usage limits" else {
                return false
            }
            guard !lowercased.contains("learn more") else {
                return false
            }

            return lowercased.contains("usage limit")
                || lowercased.contains("message limit")
                || lowercased.contains("messages remaining")
                || lowercased.contains("remaining messages")
                || lowercased.contains("remaining until")
                || lowercased.contains("limit resets")
                || lowercased.contains("limit will reset")
        }
    }

    private static func firstResetLine(from lines: [String]) -> String? {
        lines.first { line in
            guard isReasonableStatusLine(line) else {
                return false
            }

            let lowercased = line.lowercased()
            return lowercased.contains("reset") || lowercased.contains("resets")
        }
    }

    private static func isReasonableStatusLine(_ line: String) -> Bool {
        line.count <= maximumStatusLineLength && !isTemplateOrExplanatoryLine(line)
    }

    private static func isTemplateOrExplanatoryLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if trimmed.contains("{") || trimmed.contains("}") {
            return true
        }

        if trimmed.contains(#"": ""#) || trimmed.contains(#"\":\""#) {
            return true
        }

        if lowercased.contains("you're now using extra usage") {
            return true
        }

        if lowercased.contains("usage limits faster") || lowercased.contains("consumes usage") {
            return true
        }

        return false
    }

    private static func metricTitle(for line: String) -> String {
        line.lowercased().contains("reset") ? "Reset" : "Limit"
    }

    private static func looksLikeAuthPage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let authMarkers = [
            "sign in to claude",
            "log in to claude",
            "login to claude",
            "continue with google",
            "continue with email"
        ]

        return authMarkers.contains { lowercased.contains($0) }
    }

    private static func signedInAppSnapshot(from text: String) -> ProviderUsageSnapshot? {
        let lowercased = text.lowercased()
        let signedInMarkers = [
            "how can i help you today",
            "claude's choice",
            "claude’s choice",
            "moonlit chat",
            "new chat"
        ]

        guard signedInMarkers.contains(where: { lowercased.contains($0) }) else {
            return nil
        }

        return signedInSnapshot()
    }

    static func signedInSnapshot() -> ProviderUsageSnapshot {
        return ProviderUsageSnapshot(
            provider: .claude,
            planLabel: "Claude",
            primaryMetric: UsageMetric(title: "Status", value: "Signed in"),
            secondaryMetrics: [],
            fetchedAt: Date(),
            connectionState: .connected
        )
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

private extension Array where Element == UsageMetric {
    func removingDuplicateMetrics() -> [UsageMetric] {
        var seen: Set<String> = []
        return filter { metric in
            seen.insert("\(metric.title.lowercased())|\(metric.value)").inserted
        }
    }

    func normalizedUsageSettingsMetrics(sourceURL: String) -> [UsageMetric] {
        let metrics = removingDuplicateMetrics()
        guard ClaudeURLValidator.isUsageSettingsURLString(sourceURL) else {
            return metrics.sorted { first, second in
                ClaudeDashboardParser.metricPriority(first.title) < ClaudeDashboardParser.metricPriority(second.title)
            }
        }

        let usageTitles = ["Current session", "All models", "Claude Design"]
        var usageByTitle: [String: UsageMetric] = [:]
        var resetByTitle: [String: UsageMetric] = [:]

        for metric in metrics {
            if let usageTitle = Self.canonicalUsageTitle(metric.title, allowedTitles: usageTitles),
               metric.percent != nil {
                let canonicalMetric = UsageMetric(
                    title: usageTitle,
                    value: metric.value,
                    percent: metric.percent
                )
                usageByTitle[usageTitle] = Self.preferredUsageMetric(
                    current: usageByTitle[usageTitle],
                    candidate: canonicalMetric
                )
                continue
            }

            if let resetUsageTitle = Self.canonicalResetUsageTitle(metric.title, allowedTitles: usageTitles) {
                let resetTitle = resetUsageTitle.caseInsensitiveCompare("Current session") == .orderedSame
                    ? "Reset"
                    : "\(resetUsageTitle) reset"
                let canonicalMetric = UsageMetric(title: resetTitle, value: metric.value)
                resetByTitle[resetTitle] = Self.preferredResetMetric(
                    current: resetByTitle[resetTitle],
                    candidate: canonicalMetric
                )
            }
        }

        var normalized: [UsageMetric] = []
        for title in usageTitles {
            guard let usageMetric = usageByTitle[title] else {
                continue
            }

            normalized.append(usageMetric)

            let resetTitle = title.caseInsensitiveCompare("Current session") == .orderedSame
                ? "Reset"
                : "\(title) reset"
            if let resetMetric = resetByTitle[resetTitle] {
                normalized.append(resetMetric)
            }
        }

        return normalized
    }

    private static func canonicalUsageTitle(_ title: String, allowedTitles: [String]) -> String? {
        allowedTitles.first { $0.caseInsensitiveCompare(title) == .orderedSame }
    }

    private static func canonicalResetUsageTitle(_ title: String, allowedTitles: [String]) -> String? {
        if title.caseInsensitiveCompare("Reset") == .orderedSame {
            return "Current session"
        }

        let lowercasedTitle = title.lowercased()
        guard lowercasedTitle.hasSuffix(" reset") else {
            return nil
        }

        let usageTitle = String(title.dropLast(" reset".count))
        return canonicalUsageTitle(usageTitle, allowedTitles: allowedTitles)
    }

    private static func preferredUsageMetric(
        current: UsageMetric?,
        candidate: UsageMetric
    ) -> UsageMetric {
        guard let current else {
            return candidate
        }

        if (current.percent ?? 0) == 0, (candidate.percent ?? 0) > 0 {
            return candidate
        }

        return current
    }

    private static func preferredResetMetric(
        current: UsageMetric?,
        candidate: UsageMetric
    ) -> UsageMetric {
        guard let current else {
            return candidate
        }

        let currentHasTime = current.value.rangeOfCharacter(from: .decimalDigits) != nil
        let candidateHasTime = candidate.value.rangeOfCharacter(from: .decimalDigits) != nil
        return !currentHasTime && candidateHasTime ? candidate : current
    }
}
