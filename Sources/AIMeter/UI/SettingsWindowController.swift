import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(
        settingsStore: SettingsStore,
        dashboardStore: DashboardStore,
        cursorUsageCoordinator: CursorUsageCoordinator,
        claudeUsageCoordinator: ClaudeUsageCoordinator,
        launchAtLoginController: LaunchAtLoginController
    ) {
        let hostingController = NSHostingController(
            rootView: SettingsView(
                settingsStore: settingsStore,
                dashboardStore: dashboardStore,
                cursorUsageCoordinator: cursorUsageCoordinator,
                claudeUsageCoordinator: claudeUsageCoordinator,
                launchAtLoginController: launchAtLoginController
            )
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "AIMeter Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 320))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
