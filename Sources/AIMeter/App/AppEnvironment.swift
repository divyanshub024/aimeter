import Foundation

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settingsStore: SettingsStore
    let cursorSessionManager: CursorSessionManager
    let claudeSessionManager: ClaudeSessionManager
    let cursorUsageClient: CursorUsageClient
    let claudeUsageClient: ProviderUsageClient
    let cursorUsageCoordinator: CursorUsageCoordinator
    let claudeUsageCoordinator: ClaudeUsageCoordinator
    let dashboardStore: DashboardStore
    let launchAtLoginController: LaunchAtLoginController

    lazy var settingsWindowController: SettingsWindowController = {
        SettingsWindowController(
            settingsStore: settingsStore,
            dashboardStore: dashboardStore,
            cursorUsageCoordinator: cursorUsageCoordinator,
            claudeUsageCoordinator: claudeUsageCoordinator,
            launchAtLoginController: launchAtLoginController
        )
    }()
    lazy var menuBarController: MenuBarController = {
        MenuBarController(
            dashboardStore: dashboardStore,
            cursorUsageCoordinator: cursorUsageCoordinator,
            claudeUsageCoordinator: claudeUsageCoordinator,
            settingsWindowController: settingsWindowController
        )
    }()

    private init() {
        let settingsStore = SettingsStore()
        let cursorSessionManager = CursorSessionManager()
        let claudeSessionManager = ClaudeSessionManager()
        let cursorUsageClient = CursorDashboardClient(
            settingsStore: settingsStore,
            sessionManager: cursorSessionManager
        )
        let claudeUsageClient = ClaudeDashboardClient(
            settingsStore: settingsStore,
            sessionManager: claudeSessionManager
        )
        let cursorUsageCoordinator = CursorUsageCoordinator(
            settingsStore: settingsStore,
            client: cursorUsageClient
        )
        let claudeUsageCoordinator = ClaudeUsageCoordinator(
            settingsStore: settingsStore,
            client: claudeUsageClient
        )
        let dashboardStore = DashboardStore(
            settingsStore: settingsStore,
            cursorUsageCoordinator: cursorUsageCoordinator,
            claudeUsageCoordinator: claudeUsageCoordinator
        )
        let launchAtLoginController = LaunchAtLoginController()

        self.settingsStore = settingsStore
        self.cursorSessionManager = cursorSessionManager
        self.claudeSessionManager = claudeSessionManager
        self.cursorUsageClient = cursorUsageClient
        self.claudeUsageClient = claudeUsageClient
        self.cursorUsageCoordinator = cursorUsageCoordinator
        self.claudeUsageCoordinator = claudeUsageCoordinator
        self.dashboardStore = dashboardStore
        self.launchAtLoginController = launchAtLoginController
    }
}
