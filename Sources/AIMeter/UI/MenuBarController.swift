import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarController {
    private let dashboardStore: DashboardStore
    private let cursorUsageCoordinator: CursorUsageCoordinator
    private let settingsWindowController: SettingsWindowController

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(
        dashboardStore: DashboardStore,
        cursorUsageCoordinator: CursorUsageCoordinator,
        settingsWindowController: SettingsWindowController
    ) {
        self.dashboardStore = dashboardStore
        self.cursorUsageCoordinator = cursorUsageCoordinator
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
        button.image = nil
        button.imagePosition = .noImage
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 370)
        popover.contentViewController = NSHostingController(
            rootView: MenuPopoverView(
                dashboardStore: dashboardStore,
                cursorUsageCoordinator: cursorUsageCoordinator,
                onRefreshCursor: { [weak cursorUsageCoordinator] in
                    Task { await cursorUsageCoordinator?.refresh() }
                },
                onConnectCursor: { [weak cursorUsageCoordinator] in
                    Task { await cursorUsageCoordinator?.connect() }
                },
                onDisconnectCursor: { [weak cursorUsageCoordinator] in
                    cursorUsageCoordinator?.disconnect()
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

        button.image = nil
        button.attributedTitle = NSAttributedString(
            string: menuBarTitle(for: state.cursorSnapshot),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: menuBarTextColor(for: state.cursorSnapshot.connectionState)
            ]
        )

        button.toolTip = tooltip(for: state)
    }

    private func menuBarTitle(for snapshot: CursorUsageSnapshot) -> String {
        guard snapshot.hasSuccessfulSync else {
            return snapshot.connectionState == .disconnected ? "--" : "!"
        }

        return "\(Int(min(max(snapshot.totalUsedPercent, 0), 100).rounded()))%"
    }

    private func menuBarTextColor(for state: CursorConnectionState) -> NSColor {
        switch state {
        case .connected:
            return .labelColor
        case .authExpired, .syncFailed:
            return .systemOrange
        case .disconnected:
            return .secondaryLabelColor
        }
    }

    private func tooltip(for state: DashboardState) -> String {
        if state.cursorSnapshot.connectionState == .connected {
            return "Cursor: \(DisplayFormatting.percent(state.cursorSnapshot.totalUsedPercent)) - \(state.cursorSnapshot.planLabel)"
        }

        return "Cursor: \(state.cursorSnapshot.connectionState.displayText)"
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
