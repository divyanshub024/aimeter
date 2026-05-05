import XCTest
@testable import AIMeter

final class CursorURLValidatorTests: XCTestCase {
    func testAcceptsKnownCursorHTTPSHosts() throws {
        let settingsURL = try CursorURLValidator.validatedUsageURL(
            from: "https://www.cursor.com/settings"
        )
        let rootURL = try CursorURLValidator.validatedUsageURL(
            from: " https://cursor.com/settings/account "
        )

        XCTAssertEqual(settingsURL.host, "www.cursor.com")
        XCTAssertEqual(rootURL.host, "cursor.com")
    }

    func testRejectsUnsafeOrUnexpectedURLs() {
        let rejectedURLs = [
            "http://www.cursor.com/settings",
            "file:///Users/divy/private.html",
            "https://cursor.com:8443/settings",
            "https://user:pass@cursor.com/settings",
            "https://auth.cursor.com/login",
            "https://example.com/settings",
            "http://localhost:3000/settings",
            "cursor://settings"
        ]

        for rawURL in rejectedURLs {
            XCTAssertThrowsError(try CursorURLValidator.validatedUsageURL(from: rawURL), rawURL)
        }
    }

    func testSanitizesInvalidStoredURLToDefault() {
        XCTAssertEqual(
            CursorURLValidator.sanitizedUsageURL("file:///tmp/cursor.html"),
            CursorSettings.default.usagePageURL
        )
    }
}
