import XCTest
@testable import AIMeter

@MainActor
final class CursorDashboardClientTests: XCTestCase {
    func testFetchUsageRejectsInvalidURLBeforeLoadingSession() async {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        settingsStore.setCursorUsagePageURL("file:///tmp/fake-cursor.html")
        let sessionManager = SpyCursorSessionManager()
        let client = CursorDashboardClient(
            settingsStore: settingsStore,
            sessionManager: sessionManager
        )

        do {
            _ = try await client.fetchUsage()
            XCTFail("Expected invalid configuration error.")
        } catch let error as CursorUsageError {
            XCTAssertEqual(
                error,
                .invalidConfiguration("Cursor usage page URL must be an HTTPS cursor.com URL.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(sessionManager.connectedURLs.isEmpty)
        XCTAssertTrue(sessionManager.fetchedURLs.isEmpty)
    }

    func testConnectRejectsInvalidURLBeforeLoadingSession() async {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        settingsStore.setCursorUsagePageURL("http://www.cursor.com/settings")
        let sessionManager = SpyCursorSessionManager()
        let client = CursorDashboardClient(
            settingsStore: settingsStore,
            sessionManager: sessionManager
        )

        do {
            try await client.connect()
            XCTFail("Expected invalid configuration error.")
        } catch let error as CursorUsageError {
            XCTAssertEqual(
                error,
                .invalidConfiguration("Cursor usage page URL must be an HTTPS cursor.com URL.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(sessionManager.connectedURLs.isEmpty)
        XCTAssertTrue(sessionManager.fetchedURLs.isEmpty)
    }
}

@MainActor
private final class SpyCursorSessionManager: CursorSessionManaging {
    private(set) var connectedURLs: [URL] = []
    private(set) var fetchedURLs: [URL] = []

    func connect(to usagePageURL: URL) async throws -> CursorUsageSnapshot {
        connectedURLs.append(usagePageURL)
        return .disconnected
    }

    func fetchUsage(from usagePageURL: URL) async throws -> CursorUsageSnapshot {
        fetchedURLs.append(usagePageURL)
        return .disconnected
    }

    func disconnect() {}
}
