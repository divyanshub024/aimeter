import Foundation

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settingsStore: SettingsStore
    let cursorSessionManager: CursorSessionManager
    let cursorUsageClient: CursorUsageClient
    let cursorUsageCoordinator: CursorUsageCoordinator
    let dashboardStore: DashboardStore

    lazy var settingsWindowController: SettingsWindowController = {
        SettingsWindowController(
            settingsStore: settingsStore,
            dashboardStore: dashboardStore,
            cursorUsageCoordinator: cursorUsageCoordinator
        )
    }()
    lazy var menuBarController: MenuBarController = {
        MenuBarController(
            dashboardStore: dashboardStore,
            cursorUsageCoordinator: cursorUsageCoordinator,
            settingsWindowController: settingsWindowController
        )
    }()

    private init() {
        let settingsStore = SettingsStore()
        let cursorSessionManager = CursorSessionManager()
        let cursorUsageClient = CursorDashboardClient(
            settingsStore: settingsStore,
            sessionManager: cursorSessionManager
        )
        let cursorUsageCoordinator = CursorUsageCoordinator(
            settingsStore: settingsStore,
            client: cursorUsageClient
        )
        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorUsageCoordinator
        )

        self.settingsStore = settingsStore
        self.cursorSessionManager = cursorSessionManager
        self.cursorUsageClient = cursorUsageClient
        self.cursorUsageCoordinator = cursorUsageCoordinator
        self.dashboardStore = dashboardStore
    }
}
