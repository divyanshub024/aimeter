import XCTest
@testable import AIMeter

@MainActor
final class CursorUsageCoordinatorTests: XCTestCase {
    func testConnectRefreshesSnapshotImmediately() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let client = MockCursorUsageClient(
            fetchResults: [
                .success(
                    CursorUsageSnapshot(
                        planLabel: "Included in Pro+",
                        totalUsedPercent: 19,
                        autoUsedPercent: 8,
                        apiUsedPercent: 59,
                        fetchedAt: Date(timeIntervalSince1970: 100),
                        connectionState: .connected
                    )
                )
            ]
        )

        let coordinator = CursorUsageCoordinator(settingsStore: settingsStore, client: client)

        await coordinator.connect()

        XCTAssertEqual(client.connectCallCount, 1)
        XCTAssertEqual(coordinator.snapshot.connectionState, .connected)
        XCTAssertEqual(coordinator.snapshot.planLabel, "Included in Pro+")
        XCTAssertEqual(coordinator.snapshot.progressPercent ?? -1, 19, accuracy: 0.01)
    }

    func testRefreshPreservesLastSuccessfulSnapshotOnFailure() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let client = MockCursorUsageClient(
            fetchResults: [
                .success(
                    CursorUsageSnapshot(
                        planLabel: "Included in Pro+",
                        totalUsedPercent: 13,
                        autoUsedPercent: 4,
                        apiUsedPercent: 48,
                        fetchedAt: Date(timeIntervalSince1970: 100),
                        connectionState: .connected
                    )
                ),
                .failure(CursorUsageError.syncFailed("Dashboard changed"))
            ]
        )

        let coordinator = CursorUsageCoordinator(settingsStore: settingsStore, client: client)

        await coordinator.refresh()
        XCTAssertEqual(coordinator.snapshot.connectionState, .connected)

        await coordinator.refresh()
        XCTAssertEqual(coordinator.snapshot.planLabel, "Included in Pro+")
        XCTAssertEqual(coordinator.snapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(coordinator.snapshot.connectionState, .syncFailed(reason: "Dashboard changed"))
    }

    func testRefreshShowsAuthExpiredWhenNoCachedSnapshotExists() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let client = MockCursorUsageClient(fetchResults: [.failure(CursorUsageError.authExpired)])
        let coordinator = CursorUsageCoordinator(settingsStore: settingsStore, client: client)

        await coordinator.refresh()

        XCTAssertEqual(coordinator.snapshot.connectionState, .authExpired)
        XCTAssertEqual(coordinator.snapshot.totalUsedPercent, 0, accuracy: 0.01)
    }

    func testRefreshShowsInvalidConfigurationWhenURLValidationFails() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let client = MockCursorUsageClient(
            fetchResults: [
                .failure(CursorUsageError.invalidConfiguration("Cursor usage page URL must be an HTTPS cursor.com URL."))
            ]
        )
        let coordinator = CursorUsageCoordinator(settingsStore: settingsStore, client: client)

        await coordinator.refresh()

        XCTAssertEqual(
            coordinator.snapshot.connectionState,
            .syncFailed(reason: "Cursor usage page URL must be an HTTPS cursor.com URL.")
        )
    }

    func testDisconnectClearsLastSnapshot() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let client = MockCursorUsageClient(
            fetchResults: [
                .success(
                    CursorUsageSnapshot(
                        planLabel: "Included in Pro+",
                        totalUsedPercent: 13,
                        autoUsedPercent: 4,
                        apiUsedPercent: 48,
                        fetchedAt: Date(timeIntervalSince1970: 100),
                        connectionState: .connected
                    )
                )
            ]
        )

        let coordinator = CursorUsageCoordinator(settingsStore: settingsStore, client: client)

        await coordinator.refresh()
        coordinator.disconnect()

        XCTAssertEqual(coordinator.snapshot, .disconnected)
        XCTAssertEqual(client.disconnectCallCount, 1)
    }

    func testClaudeRefreshPreservesLastSuccessfulSnapshotOnFailure() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let client = MockCursorUsageClient(
            provider: .claude,
            fetchResults: [
                .success(
                    ProviderUsageSnapshot(
                        provider: .claude,
                        planLabel: "Claude Pro",
                        primaryMetric: UsageMetric(title: "Usage", value: "42%", percent: 42),
                        secondaryMetrics: [UsageMetric(title: "Reset", value: "Resets at 5 PM")],
                        fetchedAt: Date(timeIntervalSince1970: 100),
                        connectionState: .connected
                    )
                ),
                .failure(CursorUsageError.syncFailed("Claude layout changed"))
            ]
        )

        let coordinator = ClaudeUsageCoordinator(settingsStore: settingsStore, client: client)

        await coordinator.refresh()
        XCTAssertEqual(coordinator.snapshot.connectionState, .connected)

        await coordinator.refresh()
        XCTAssertEqual(coordinator.snapshot.provider, .claude)
        XCTAssertEqual(coordinator.snapshot.planLabel, "Claude Pro")
        XCTAssertEqual(coordinator.snapshot.progressPercent ?? -1, 42, accuracy: 0.01)
        XCTAssertEqual(coordinator.snapshot.connectionState, .syncFailed(reason: "Claude layout changed"))
    }
}

@MainActor
private final class MockCursorUsageClient: CursorUsageClient {
    let provider: UsageProvider
    var connectCallCount = 0
    var disconnectCallCount = 0

    private var fetchResults: [Result<CursorUsageSnapshot, Error>]

    init(
        provider: UsageProvider = .cursor,
        fetchResults: [Result<CursorUsageSnapshot, Error>]
    ) {
        self.provider = provider
        self.fetchResults = fetchResults
    }

    func connect() async throws {
        connectCallCount += 1
    }

    func fetchUsage() async throws -> CursorUsageSnapshot {
        guard !fetchResults.isEmpty else {
            throw CursorUsageError.syncFailed("No mock result configured")
        }

        let result = fetchResults.removeFirst()
        return try result.get()
    }

    func disconnect() {
        disconnectCallCount += 1
    }
}
