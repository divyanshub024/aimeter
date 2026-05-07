import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController {
    private let dashboardStore: DashboardStore
    private let cursorUsageCoordinator: CursorUsageCoordinator
    private let claudeUsageCoordinator: ClaudeUsageCoordinator
    private let settingsWindowController: SettingsWindowController

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(
        dashboardStore: DashboardStore,
        cursorUsageCoordinator: CursorUsageCoordinator,
        claudeUsageCoordinator: ClaudeUsageCoordinator,
        settingsWindowController: SettingsWindowController
    ) {
        self.dashboardStore = dashboardStore
        self.cursorUsageCoordinator = cursorUsageCoordinator
        self.claudeUsageCoordinator = claudeUsageCoordinator
        self.settingsWindowController = settingsWindowController
    }

    func install() {
        configureStatusItem()
        configurePopover()
        bindDashboard()
        updateStatusItem(dashboardStore.state)
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "AIMeter.StatusItem"

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.imagePosition = .imageOnly
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = preferredPopoverSize(for: dashboardStore.state)
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                dashboardStore: dashboardStore,
                cursorUsageCoordinator: cursorUsageCoordinator,
                claudeUsageCoordinator: claudeUsageCoordinator,
                onRefreshCursor: { [weak cursorUsageCoordinator] in
                    Task { await cursorUsageCoordinator?.refresh() }
                },
                onRefreshClaude: { [weak claudeUsageCoordinator] in
                    Task { await claudeUsageCoordinator?.refresh() }
                },
                onConnectCursor: { [weak cursorUsageCoordinator] in
                    Task { await cursorUsageCoordinator?.connect() }
                },
                onConnectClaude: { [weak claudeUsageCoordinator] in
                    Task { await claudeUsageCoordinator?.connect() }
                },
                onDisconnectCursor: { [weak cursorUsageCoordinator] in
                    cursorUsageCoordinator?.disconnect()
                },
                onDisconnectClaude: { [weak claudeUsageCoordinator] in
                    claudeUsageCoordinator?.disconnect()
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
        )
    }

    private func bindDashboard() {
        dashboardStore.$state
            .sink { [weak self] state in
                self?.updateStatusItem(state)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(_ state: DashboardState) {
        guard let button = statusItem.button else { return }

        popover.contentSize = preferredPopoverSize(for: state)

        button.image = StatusBarImageFactory.image(
            progress: state.menuBarProgressPercent / 100,
            state: primaryConnectionState(for: state)
        )
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")

        button.toolTip = tooltip(for: state)
    }

    private func preferredPopoverSize(for state: DashboardState) -> NSSize {
        let connectedProviderCount = state.connectedProviderSnapshots.count
        let height: CGFloat
        if state.presentationState == .firstRun || connectedProviderCount == 0 {
            height = 420
        } else {
            height = connectedProviderCount == 1 ? 370 : 560
        }

        return NSSize(width: 380, height: height)
    }

    private func tooltip(for state: DashboardState) -> String {
        let connectedSnapshots = state.connectedProviderSnapshots
        guard !connectedSnapshots.isEmpty else {
            return "AIMeter: Connect Cursor or Claude"
        }

        return connectedSnapshots
            .map { snapshot in
                if let progressPercent = snapshot.progressPercent, snapshot.connectionState == .connected {
                    return "\(snapshot.provider.displayName): \(DisplayFormatting.percent(progressPercent)) - \(snapshot.planLabel)"
                }

                return "\(snapshot.provider.displayName): \(snapshot.connectionState.displayText)"
            }
            .joined(separator: "\n")
    }

    private func primaryConnectionState(for state: DashboardState) -> ProviderConnectionState {
        let connectedWithProgress = state.connectedProviderSnapshots
            .filter { $0.connectionState == .connected && $0.progressPercent != nil }

        if !connectedWithProgress.isEmpty {
            return .connected
        }

        return .disconnected
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            installEventMonitors()
        }
    }

    private func openSettings() {
        closePopover(nil)
        settingsWindowController.show()
    }

    private func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        removeEventMonitors()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, self.shouldClosePopover(for: event) {
                    self.closePopover(nil)
                }
            }

            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover(nil)
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else {
            return false
        }

        if let popoverWindow = popover.contentViewController?.view.window,
           event.window === popoverWindow {
            return false
        }

        if let statusItemWindow = statusItem.button?.window,
           event.window === statusItemWindow {
            return false
        }

        return true
    }
}

private enum StatusBarImageFactory {
    static func image(progress: Double, state: CursorConnectionState) -> NSImage {
        let size = NSSize(width: 34, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        let barRect = NSRect(x: 4, y: 4, width: 22, height: 8)
        drawBar(rect: barRect, progress: progress, color: .systemBlue, isConnected: state == .connected)
        drawIndicator(atX: 29, state: state)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawBar(rect: NSRect, progress: Double, color: NSColor, isConnected: Bool) {
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.tertiaryLabelColor.withAlphaComponent(isConnected ? 0.25 : 0.12).setFill()
        backgroundPath.fill()

        guard isConnected else {
            return
        }

        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else {
            return
        }

        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * clamped, height: rect.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 4, yRadius: 4)
        color.setFill()
        fillPath.fill()
    }

    private static func drawIndicator(atX x: CGFloat, state: CursorConnectionState) {
        guard state != .connected else { return }

        let indicatorRect = NSRect(x: x, y: 6, width: 4, height: 4)
        let indicatorPath = NSBezierPath(ovalIn: indicatorRect)
        indicatorColor(for: state).setFill()
        indicatorPath.fill()
    }

    private static func indicatorColor(for state: CursorConnectionState) -> NSColor {
        switch state {
        case .authExpired, .syncFailed:
            return .systemOrange
        case .disconnected:
            return .systemYellow
        case .connected:
            return .clear
        }
    }
}
