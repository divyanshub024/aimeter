import SwiftUI

@main
struct AIMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let environment = AppEnvironment.shared

    var body: some Scene {
        Settings {
            SettingsView(
                settingsStore: environment.settingsStore,
                dashboardStore: environment.dashboardStore,
                cursorUsageCoordinator: environment.cursorUsageCoordinator
            )
        }
    }
}
