import XCTest
@testable import AIMeter

final class CursorDashboardParserTests: XCTestCase {
    func testParsesDOMTextFixture() {
        let text = """
        Included in Pro+
        Total
        13%
        4% Auto and 48% API used
        """

        let result = CursorDashboardParser.parseDOMText(text, sourceURL: "https://www.cursor.com/settings")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.planLabel, "Included in Pro+")
        XCTAssertEqual(snapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(snapshot.autoUsedPercent, 4, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 48, accuracy: 0.01)
        XCTAssertEqual(snapshot.connectionState, .connected)
    }

    func testParsesJSONPayloadFixture() {
        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "breakdown": {
              "autoUsedPercent": 0.04,
              "apiUsedPercent": 0.48
            }
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(payload, sourceURL: "https://www.cursor.com/settings")

        guard case .usage(let snapshot) = result else {
            return XCTFail("Expected parsed usage snapshot.")
        }

        XCTAssertEqual(snapshot.planLabel, "Included in Pro+")
        XCTAssertEqual(snapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(snapshot.autoUsedPercent, 4, accuracy: 0.01)
        XCTAssertEqual(snapshot.apiUsedPercent, 48, accuracy: 0.01)
    }

    func testRejectsPartialDashboardData() {
        let text = """
        Included in Pro+
        Total
        13%
        """

        let result = CursorDashboardParser.parseDOMText(text, sourceURL: "https://www.cursor.com/settings")

        XCTAssertEqual(result, .noMatch)
    }

    func testDetectsAuthenticationPage() {
        let text = """
        Sign in to Cursor
        Continue with GitHub
        """

        let result = CursorDashboardParser.parseDOMText(text, sourceURL: "https://auth.cursor.com/login")

        XCTAssertEqual(result, .authRequired)
    }

    func testDoesNotTreatAuthSubrequestPayloadAsExpiredSession() {
        let payload = """
        {
          "provider": "auth0",
          "screen_hint": "continue with github"
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://www.cursor.com/api/auth/session"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testRejectsUsageShapedPayloadsFromNonCursorHosts() {
        let payload = """
        {
          "plan": {
            "label": "Included in Pro+"
          },
          "usage": {
            "totalUsedPercent": 0.13,
            "autoUsedPercent": 0.04,
            "apiUsedPercent": 0.48
          }
        }
        """

        let result = CursorDashboardParser.parseResponseBody(
            payload,
            sourceURL: "https://example.com/api/usage"
        )

        XCTAssertEqual(result, .noMatch)
    }

    func testTreatsNormalAuthRedirectNavigationErrorsAsBenign() {
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        let frameLoadInterrupted = NSError(domain: "WebKitErrorDomain", code: 102)
        let hostFailure = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)

        XCTAssertTrue(CursorWebViewScraper.isBenignNavigationError(cancelled))
        XCTAssertTrue(CursorWebViewScraper.isBenignNavigationError(frameLoadInterrupted))
        XCTAssertFalse(CursorWebViewScraper.isBenignNavigationError(hostFailure))
    }
}
