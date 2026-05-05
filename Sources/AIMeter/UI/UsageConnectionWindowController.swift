import AppKit
import WebKit

@MainActor
final class UsageConnectionWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(title: String, webView: WKWebView) {
        let viewController = NSViewController()
        viewController.view = webView

        let window = NSWindow(contentViewController: viewController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1180, height: 860))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
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

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
