import XCTest
@testable import AIMeter

@MainActor
final class DashboardStoreTests: XCTestCase {
    func testDashboardStateTracksCursorUsage() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let cursorClient = DashboardMockCursorUsageClient(
            fetchResults: [
                .success(
                    CursorUsageSnapshot(
                        planLabel: "Included in Pro+",
                        totalUsedPercent: 13,
                        autoUsedPercent: 4,
                        apiUsedPercent: 48,
                        fetchedAt: fetchedAt,
                        connectionState: .connected
                    )
                )
            ]
        )

        let cursorCoordinator = CursorUsageCoordinator(settingsStore: settingsStore, client: cursorClient)
        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorCoordinator
        )

        await cursorCoordinator.refresh()

        XCTAssertEqual(dashboardStore.state.presentationState, .dashboard)
        XCTAssertEqual(dashboardStore.state.cursorSnapshot.planLabel, "Included in Pro+")
        XCTAssertEqual(dashboardStore.state.cursorSnapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(dashboardStore.state.lastRefreshAt, fetchedAt)
        XCTAssertTrue(settingsStore.settings.hasCompletedInitialSetup)
    }

    func testDashboardStateStartsInFirstRunMode() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let cursorCoordinator = CursorUsageCoordinator(
            settingsStore: settingsStore,
            client: DashboardMockCursorUsageClient(fetchResults: [])
        )

        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorCoordinator
        )

        XCTAssertEqual(dashboardStore.state.presentationState, .firstRun)
    }

    func testCompletedSetupKeepsDashboardVisibleWhenCursorDisconnects() {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        settingsStore.markInitialSetupComplete()
        let cursorCoordinator = CursorUsageCoordinator(
            settingsStore: settingsStore,
            client: DashboardMockCursorUsageClient(fetchResults: [])
        )

        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorCoordinator
        )

        XCTAssertEqual(dashboardStore.state.presentationState, .dashboard)
        XCTAssertEqual(dashboardStore.state.cursorSnapshot.connectionState, .disconnected)
    }
}

@MainActor
private final class DashboardMockCursorUsageClient: CursorUsageClient {
    private var fetchResults: [Result<CursorUsageSnapshot, Error>]

    init(fetchResults: [Result<CursorUsageSnapshot, Error>]) {
        self.fetchResults = fetchResults
    }

    func connect() async throws {}

    func fetchUsage() async throws -> CursorUsageSnapshot {
        let result = fetchResults.removeFirst()
        return try result.get()
    }

    func disconnect() {}
}
