import XCTest
@testable import AIMeter

final class ClaudeURLValidatorTests: XCTestCase {
    func testAcceptsKnownClaudeHTTPSHosts() throws {
        let rootURL = try ClaudeURLValidator.validatedUsageURL(from: "https://claude.ai")
        let wwwURL = try ClaudeURLValidator.validatedUsageURL(from: " https://www.claude.ai/settings ")

        XCTAssertEqual(rootURL.host, "claude.ai")
        XCTAssertEqual(wwwURL.host, "www.claude.ai")
    }

    func testRejectsUnsafeOrUnexpectedURLs() {
        let rejectedURLs = [
            "http://claude.ai",
            "file:///Users/divy/private.html",
            "https://claude.ai:8443/settings",
            "https://user:pass@claude.ai/settings",
            "https://api.anthropic.com/usage",
            "https://example.com/settings",
            "http://localhost:3000/settings",
            "claude://settings"
        ]

        for rawURL in rejectedURLs {
            XCTAssertThrowsError(try ClaudeURLValidator.validatedUsageURL(from: rawURL), rawURL)
        }
    }

    func testSanitizesInvalidStoredURLToDefault() {
        XCTAssertEqual(
            ClaudeURLValidator.sanitizedUsageURL("file:///tmp/claude.html"),
            ClaudeSettings.default.usagePageURL
        )
    }

    func testSanitizesRootURLToUsageSettings() {
        XCTAssertEqual(
            ClaudeURLValidator.sanitizedUsageURL("https://claude.ai"),
            "https://claude.ai/settings/usage"
        )
    }
}
