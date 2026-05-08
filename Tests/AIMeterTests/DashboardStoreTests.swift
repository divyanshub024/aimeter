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

    func testDashboardTracksMultipleProvidersAndUsesHighestMenuBarProgress() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let cursorCoordinator = CursorUsageCoordinator(
            settingsStore: settingsStore,
            client: DashboardMockCursorUsageClient(
                provider: .cursor,
                fetchResults: [
                    .success(
                        CursorUsageSnapshot(
                            planLabel: "Cursor Plan",
                            totalUsedPercent: 13,
                            autoUsedPercent: 4,
                            apiUsedPercent: 48,
                            fetchedAt: Date(timeIntervalSince1970: 100),
                            connectionState: .connected
                        )
                    )
                ]
            )
        )
        let claudeCoordinator = ClaudeUsageCoordinator(
            settingsStore: settingsStore,
            client: DashboardMockCursorUsageClient(
                provider: .claude,
                fetchResults: [
                    .success(
                        ProviderUsageSnapshot(
                            provider: .claude,
                            planLabel: "Claude Pro",
                            primaryMetric: UsageMetric(title: "Usage", value: "82%", percent: 82),
                            secondaryMetrics: [],
                            fetchedAt: Date(timeIntervalSince1970: 200),
                            connectionState: .connected
                        )
                    )
                ]
            )
        )

        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorCoordinator,
            claudeUsageCoordinator: claudeCoordinator
        )

        await cursorCoordinator.refresh()
        await claudeCoordinator.refresh()

        XCTAssertEqual(dashboardStore.state.presentationState, .dashboard)
        XCTAssertEqual(dashboardStore.state.cursorSnapshot.totalUsedPercent, 13, accuracy: 0.01)
        XCTAssertEqual(dashboardStore.state.claudeSnapshot.progressPercent ?? -1, 82, accuracy: 0.01)
        XCTAssertEqual(dashboardStore.state.connectedProviderSnapshots.map(\.provider), [.cursor, .claude])
        XCTAssertEqual(dashboardStore.state.menuBarProgressPercent, 82, accuracy: 0.01)
        XCTAssertEqual(dashboardStore.state.lastRefreshAt, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(settingsStore.settings.hasCompletedInitialSetup)
    }

    func testDisconnectingClaudeDoesNotClearCursorState() async {
        let userDefaults = UserDefaults(suiteName: #function)!
        userDefaults.removePersistentDomain(forName: #function)

        let settingsStore = SettingsStore(userDefaults: userDefaults)
        let cursorCoordinator = CursorUsageCoordinator(
            settingsStore: settingsStore,
            client: DashboardMockCursorUsageClient(
                provider: .cursor,
                fetchResults: [
                    .success(
                        CursorUsageSnapshot(
                            planLabel: "Cursor Plan",
                            totalUsedPercent: 19,
                            autoUsedPercent: 8,
                            apiUsedPercent: 59,
                            fetchedAt: Date(timeIntervalSince1970: 100),
                            connectionState: .connected
                        )
                    )
                ]
            )
        )
        let claudeClient = DashboardMockCursorUsageClient(
            provider: .claude,
            fetchResults: [
                .success(
                    ProviderUsageSnapshot(
                        provider: .claude,
                        planLabel: "Claude Pro",
                        primaryMetric: UsageMetric(title: "Usage", value: "42%", percent: 42),
                        secondaryMetrics: [],
                        fetchedAt: Date(timeIntervalSince1970: 200),
                        connectionState: .connected
                    )
                )
            ]
        )
        let claudeCoordinator = ClaudeUsageCoordinator(settingsStore: settingsStore, client: claudeClient)
        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorCoordinator,
            claudeUsageCoordinator: claudeCoordinator
        )

        await cursorCoordinator.refresh()
        await claudeCoordinator.refresh()
        claudeCoordinator.disconnect()

        XCTAssertEqual(dashboardStore.state.cursorSnapshot.connectionState, .connected)
        XCTAssertEqual(dashboardStore.state.cursorSnapshot.totalUsedPercent, 19, accuracy: 0.01)
        XCTAssertEqual(dashboardStore.state.connectedProviderSnapshots.map(\.provider), [.cursor])
        XCTAssertEqual(dashboardStore.state.menuBarProgressPercent, 19, accuracy: 0.01)
        XCTAssertEqual(dashboardStore.state.claudeSnapshot.connectionState, .disconnected)
        XCTAssertEqual(dashboardStore.state.claudeSnapshot.progressPercent, nil)
    }

    func testMenuBarProgressIgnoresExpiredProviderSnapshots() {
        let state = DashboardState(
            presentationState: .dashboard,
            providerSnapshots: [
                CursorUsageSnapshot(
                    planLabel: "Cursor Plan",
                    totalUsedPercent: 19,
                    autoUsedPercent: 8,
                    apiUsedPercent: 59,
                    fetchedAt: Date(timeIntervalSince1970: 100),
                    connectionState: .connected
                ),
                ProviderUsageSnapshot(
                    provider: .claude,
                    planLabel: "Claude Pro",
                    primaryMetric: UsageMetric(title: "Usage", value: "99%", percent: 99),
                    secondaryMetrics: [],
                    fetchedAt: Date(timeIntervalSince1970: 200),
                    connectionState: .authExpired
                )
            ],
            lastRefreshAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(state.connectedProviderSnapshots.map(\.provider), [.cursor, .claude])
        XCTAssertEqual(state.menuBarProgressPercent, 19, accuracy: 0.01)
    }

    func testUnsyncedExpiredProviderSnapshotIsHiddenFromPopover() {
        let state = DashboardState(
            presentationState: .dashboard,
            providerSnapshots: [
                DashboardState.defaultSnapshot(for: .cursor).withConnectionState(.authExpired),
                ProviderUsageSnapshot(
                    provider: .claude,
                    planLabel: "Claude Pro",
                    primaryMetric: UsageMetric(title: "Usage", value: "54%", percent: 54),
                    secondaryMetrics: [],
                    fetchedAt: Date(timeIntervalSince1970: 200),
                    connectionState: .connected
                )
            ],
            lastRefreshAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(state.connectedProviderSnapshots.map(\.provider), [.claude])
    }
}

@MainActor
private final class DashboardMockCursorUsageClient: CursorUsageClient {
    let provider: UsageProvider
    private var fetchResults: [Result<CursorUsageSnapshot, Error>]

    init(
        provider: UsageProvider = .cursor,
        fetchResults: [Result<CursorUsageSnapshot, Error>]
    ) {
        self.provider = provider
        self.fetchResults = fetchResults
    }

    func connect() async throws {}

    func fetchUsage() async throws -> CursorUsageSnapshot {
        let result = fetchResults.removeFirst()
        return try result.get()
    }

    func disconnect() {}
}
