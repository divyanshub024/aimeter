import XCTest
@testable import AIMeter

@MainActor
final class ClaudeDashboardClientTests: XCTestCase {
    func testFetchUsageRejectsInvalidURLBeforeLoadingSession() async {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        settingsStore.setClaudeUsagePageURL("file:///tmp/fake-claude.html")
        let sessionManager = SpyClaudeSessionManager()
        let client = ClaudeDashboardClient(
            settingsStore: settingsStore,
            sessionManager: sessionManager
        )

        do {
            _ = try await client.fetchUsage()
            XCTFail("Expected invalid configuration error.")
        } catch let error as ProviderUsageError {
            XCTAssertEqual(
                error,
                .invalidConfiguration("Claude usage page URL must be an HTTPS claude.ai URL.")
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
        settingsStore.setClaudeUsagePageURL("http://claude.ai")
        let sessionManager = SpyClaudeSessionManager()
        let client = ClaudeDashboardClient(
            settingsStore: settingsStore,
            sessionManager: sessionManager
        )

        do {
            try await client.connect()
            XCTFail("Expected invalid configuration error.")
        } catch let error as ProviderUsageError {
            XCTAssertEqual(
                error,
                .invalidConfiguration("Claude usage page URL must be an HTTPS claude.ai URL.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(sessionManager.connectedURLs.isEmpty)
        XCTAssertTrue(sessionManager.fetchedURLs.isEmpty)
    }

    func testFetchAfterSignInOnlyConnectLoadsUsagePage() async throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let sessionManager = SpyClaudeSessionManager()
        sessionManager.connectResult = ClaudeDashboardParser.signedInSnapshot()
        sessionManager.fetchResult = ProviderUsageSnapshot(
            provider: .claude,
            planLabel: "Claude Max plan",
            primaryMetric: UsageMetric(title: "Current session", value: "73%", percent: 73),
            secondaryMetrics: [],
            fetchedAt: Date(),
            connectionState: .connected
        )
        let client = ClaudeDashboardClient(
            settingsStore: settingsStore,
            sessionManager: sessionManager
        )

        try await client.connect()
        let snapshot = try await client.fetchUsage()

        XCTAssertEqual(snapshot.primaryMetric.title, "Current session")
        XCTAssertEqual(snapshot.progressPercent ?? -1, 73, accuracy: 0.01)
        XCTAssertEqual(sessionManager.connectedURLs.count, 1)
        XCTAssertEqual(sessionManager.fetchedURLs.count, 1)
    }
}

@MainActor
private final class SpyClaudeSessionManager: ClaudeSessionManaging {
    private(set) var connectedURLs: [URL] = []
    private(set) var fetchedURLs: [URL] = []
    var connectResult = ProviderUsageSnapshot.claudeDisconnected
    var fetchResult = ProviderUsageSnapshot.claudeDisconnected

    func connect(to usagePageURL: URL) async throws -> ProviderUsageSnapshot {
        connectedURLs.append(usagePageURL)
        return connectResult
    }

    func fetchUsage(from usagePageURL: URL) async throws -> ProviderUsageSnapshot {
        fetchedURLs.append(usagePageURL)
        return fetchResult
    }

    func disconnect() {}
}
