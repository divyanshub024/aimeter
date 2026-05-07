import XCTest
@testable import AIMeter

final class ClaudeDashboardParserTests: XCTestCase {
    func testParsesPercentageUsageText() {
        let text = """
        Claude Pro
        Usage
        42.5% used
        Resets at 5 PM
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed Claude usage snapshot.")
        }

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.planLabel, "Claude Pro")
        XCTAssertEqual(snapshot.primaryMetric.title, "Usage")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 42.5, accuracy: 0.01)
        XCTAssertEqual(snapshot.connectionState, .connected)
    }

    func testParsesSettingsUsagePageRows() {
        let text = """
        Settings
        Plan usage limits
        Pro
        Current session
        Resets in 53 min
        Opus consumes usage limits faster than other models
        73% used
        Weekly limits
        Learn more about usage limits
        All models
        Resets Sun 11:30 AM
        50% used
        Claude Design
        Resets Sun 11:29 AM
        7% used
        Extra usage
        $0.00 spent
        0% used
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected Claude usage settings rows to parse.")
        }

        XCTAssertEqual(snapshot.primaryMetric.title, "Current session")
        XCTAssertEqual(snapshot.planLabel, "Claude Pro")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 73, accuracy: 0.01)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Reset" }?.value, "Resets in 53 min")
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "All models" }?.percent, 50)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "All models reset" }?.value, "Resets Sun 11:30 AM")
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Claude Design" }?.percent, 7)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Claude Design reset" }?.value, "Resets Sun 11:29 AM")
        XCTAssertNil(snapshot.secondaryMetrics.first { $0.title == "Extra usage" })
        XCTAssertNil(snapshot.secondaryMetrics.first { $0.title == "Usage" })
        XCTAssertNil(snapshot.secondaryMetrics.first { $0.title == "Limit" })
    }

    func testLabelsUnlabeledSettingsUsagePercentagesByPageOrder() {
        let text = """
        Settings
        Plan usage limits
        Pro
        73% used
        50% used
        7% used
        0% used
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected Claude usage settings percentages to parse.")
        }

        XCTAssertEqual(snapshot.planLabel, "Claude Pro")
        XCTAssertEqual(snapshot.primaryMetric.title, "Current session")
        XCTAssertEqual(snapshot.primaryMetric.percent, 73)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "All models" }?.percent, 50)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Claude Design" }?.percent, 7)
        XCTAssertNil(snapshot.secondaryMetrics.first { $0.title == "Extra usage" })
        XCTAssertNil(snapshot.secondaryMetrics.first { $0.title == "Usage" })
    }

    func testParsesSettingsUsageRowsWithBarePercentLines() {
        let text = """
        Settings
        Plan usage limits
        Pro
        Current session
        Resets in 2 hr 23 min
        23%
        Weekly limits
        All models
        Resets Sun 11:30 AM
        54%
        Claude Design
        Resets Sun 11:30 AM
        7%
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected Claude usage settings rows to parse from bare percent lines.")
        }

        XCTAssertEqual(snapshot.primaryMetric.title, "Current session")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 23, accuracy: 0.01)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Reset" }?.value, "Resets in 2 hr 23 min")
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "All models" }?.percent, 54)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "All models reset" }?.value, "Resets Sun 11:30 AM")
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Claude Design" }?.percent, 7)
        XCTAssertNil(snapshot.secondaryMetrics.first { $0.title == "Limit" })
    }

    func testDeduplicatesRepeatedSettingsUsageRows() {
        let text = """
        Settings
        Plan usage limits
        Pro
        Current session
        Resets in 1 hr 4 min
        27% used
        All models
        Resets Sun 11:30 AM
        55% used
        Claude Design
        Resets Sun 11:29 AM
        7% used
        Claude Design
        Resets Sun 11:29 AM
        7% used
        All models
        Resets Sun 11:30 AM
        55% used
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected repeated Claude usage settings rows to parse.")
        }

        XCTAssertEqual(snapshot.secondaryMetrics.filter { $0.title == "All models" }.count, 1)
        XCTAssertEqual(snapshot.secondaryMetrics.filter { $0.title == "All models reset" }.count, 1)
        XCTAssertEqual(snapshot.secondaryMetrics.filter { $0.title == "Claude Design" }.count, 1)
        XCTAssertEqual(snapshot.secondaryMetrics.filter { $0.title == "Claude Design reset" }.count, 1)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "All models" }?.percent, 55)
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Claude Design" }?.percent, 7)
    }

    func testKeepsClaudeUsageSettingsMetricsInStaticOrder() {
        let text = """
        Settings
        Plan usage limits
        Pro
        Claude Design
        Resets Sun 11:29 AM
        7% used
        All models
        Resets Sun 11:30 AM
        55% used
        Current session
        Resets in 1 hr 4 min
        27% used
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected reordered Claude usage settings rows to parse.")
        }

        XCTAssertEqual(snapshot.primaryMetric.title, "Current session")
        XCTAssertEqual(snapshot.secondaryMetrics.filter { $0.percent != nil }.map(\.title), [
            "All models",
            "Claude Design"
        ])
        XCTAssertEqual(snapshot.secondaryMetrics.first { $0.title == "Reset" }?.value, "Resets in 1 hr 4 min")
    }

    func testParsesLimitTextWithoutPercentage() {
        let text = """
        Claude Max
        Your usage limit resets at 3 PM
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://www.claude.ai/settings")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected text-only Claude usage snapshot.")
        }

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.planLabel, "Claude Max")
        XCTAssertEqual(snapshot.primaryMetric.title, "Limit")
        XCTAssertNil(snapshot.progressPercent)
        XCTAssertTrue(snapshot.primaryMetric.value.localizedCaseInsensitiveContains("resets"))
    }

    func testTreatsSignedInClaudeHomeAsConnected() {
        let text = """
        Moonlit chat?
        How can I help you today?
        Write
        Learn
        Code
        Claude’s choice
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected signed-in Claude home to count as connected.")
        }

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.connectionState, .connected)
        XCTAssertEqual(snapshot.primaryMetric.value, "Signed in")
        XCTAssertNil(snapshot.progressPercent)
    }

    func testDoesNotTreatUsageSettingsShellAsSignedInUsage() {
        let text = """
        Claude
        New chat
        Search
        Chats
        Projects
        Settings
        Usage
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        XCTAssertEqual(result, .noMatch)
    }

    func testDetectsAuthenticationPage() {
        let text = """
        Sign in to Claude
        Continue with Google
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/login")

        XCTAssertEqual(result, .authRequired)
    }

    func testRejectsUsageShapedPayloadsFromNonClaudeHosts() {
        let payload = """
        {
          "plan": "Claude Pro",
          "usage": "91% used"
        }
        """

        let result = ClaudeDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://example.com/api/usage"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testDoesNotTreatAuthProviderPayloadAsExpiredSession() {
        let payload = """
        {
          "provider": "google",
          "screen": "continue with google"
        }
        """

        let result = ClaudeDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://claude.ai/api/auth/session"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testParsesClaudeJSONPayload() {
        let payload = """
        {
          "plan": "Claude Pro",
          "usage": "Usage limit 72% used",
          "reset": "Resets at 5 PM"
        }
        """

        let result = ClaudeDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://claude.ai/api/usage"
        )

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed Claude usage snapshot.")
        }

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.planLabel, "Claude Pro")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 72, accuracy: 0.01)
    }

    func testRejectsClaudeTemplatePayloadWithoutVisibleUsagePercent() {
        let payload = """
        {
          "+7AsHII/pl": "You're now using extra usage • Your weekly limit resets {day} at {time}",
          "plan": "Claude Max plan"
        }
        """

        let result = ClaudeDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://claude.ai/api/bootstrap"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testRejectsClaudeExplanatoryUsageLimitCopy() {
        let text = """
        Claude
        Claude Max plan
        Opus consumes usage limits faster than other models
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        XCTAssertEqual(result, .noMatch)
    }

    func testTemplateLimitCopyDoesNotBecomePrimaryUsage() {
        let text = """
        Claude Max plan
        "+7AsHII/pl": "You're now using extra usage • Your weekly limit resets {day} at {time}"
        Current session
        Resets in 53 min
        73% used
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai/settings/usage")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected visible Claude usage rows to parse.")
        }

        XCTAssertEqual(snapshot.primaryMetric.title, "Current session")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 73, accuracy: 0.01)
    }

    func testRejectsGenericClaudePageCopy() {
        let text = """
        Claude
        Default responses from Claude
        Explain why the sky changes color at sunset
        Most efficient for everyday tasks
        Upload CSVs for Claude to analyze quantitative data with high accuracy and create interactive data visualizations.
        Concise Our most intelligent model yet Auto thinking Shorter responses & more messages Best for most use cases Normal Best for math and coding challenges Short Story Most capable for ambitious work
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai")

        XCTAssertEqual(result, .noMatch)
    }

    func testRejectsPlanOnlyClaudePageText() {
        let text = """
        Claude Pro
        Best for most use cases
        Shorter responses and more messages
        """

        let result = ClaudeDashboardParser.parseDOMText(text, sourceURL: "https://claude.ai")

        XCTAssertEqual(result, .noMatch)
    }
}
