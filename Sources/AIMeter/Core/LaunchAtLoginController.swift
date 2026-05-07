import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case notRegistered
    case notFound
    case requiresApproval
}

protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    private let service: LaunchAtLoginServicing
    private let userDefaults: UserDefaults
    private let shouldEnableByDefault: Bool
    private let defaultAppliedKey = "aimeter.launchAtLogin.defaultApplied"

    init(
        service: LaunchAtLoginServicing = MainAppLoginItemService(),
        userDefaults: UserDefaults = .standard,
        shouldEnableByDefault: Bool = true
    ) {
        self.service = service
        self.userDefaults = userDefaults
        self.shouldEnableByDefault = shouldEnableByDefault
        applyDefaultIfNeeded()
        refresh()
    }

    func refresh() {
        apply(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }

            refresh()
        } catch {
            refresh()
            statusMessage = "Could not update Login Items: \(error.localizedDescription)"
        }
    }

    private func apply(_ status: LaunchAtLoginStatus) {
        switch status {
        case .enabled:
            isEnabled = true
            statusMessage = nil
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Approve AIMeter in System Settings > General > Login Items to start it at login."
        case .notRegistered, .notFound:
            isEnabled = false
            statusMessage = nil
        }
    }

    private func applyDefaultIfNeeded() {
        guard shouldEnableByDefault, !userDefaults.bool(forKey: defaultAppliedKey) else {
            return
        }

        switch service.status {
        case .notRegistered, .notFound:
            do {
                try service.register()
                userDefaults.set(true, forKey: defaultAppliedKey)
            } catch {
                statusMessage = "Could not update Login Items: \(error.localizedDescription)"
            }
        case .enabled, .requiresApproval:
            userDefaults.set(true, forKey: defaultAppliedKey)
            break
        }
    }
}

private struct MainAppLoginItemService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        case .notRegistered:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
