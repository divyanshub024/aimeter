import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared
        environment.menuBarController.install()
        environment.cursorUsageCoordinator.start()
        environment.claudeUsageCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            AppEnvironment.shared.cursorUsageCoordinator.stop()
            AppEnvironment.shared.claudeUsageCoordinator.stop()
        }
    }
}
