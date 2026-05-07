import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared
        environment.menuBarController.install()
        environment.cursorUsageCoordinator.start()
        environment.claudeUsageCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let environment = AppEnvironment.shared
        environment.cursorUsageCoordinator.stop()
        environment.claudeUsageCoordinator.stop()
    }
}
