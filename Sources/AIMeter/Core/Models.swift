import Foundation

struct AppSettings: Codable, Equatable {
    var pollIntervalSeconds: TimeInterval
    var hasCompletedInitialSetup: Bool
    var cursor: CursorSettings

    static let `default` = AppSettings(
        pollIntervalSeconds: 300,
        hasCompletedInitialSetup: false,
        cursor: .default
    )
}

struct CursorSettings: Codable, Equatable {
    var usagePageURL: String

    static let `default` = CursorSettings(
        usagePageURL: "https://www.cursor.com/settings"
    )
}

enum CursorConnectionState: Equatable {
    case disconnected
    case connected
    case authExpired
    case syncFailed(reason: String)

    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connected:
            return "Connected"
        case .authExpired:
            return "Session expired"
        case .syncFailed(let reason):
            return reason
        }
    }
}

struct CursorUsageSnapshot: Equatable {
    let planLabel: String
    let totalUsedPercent: Double
    let autoUsedPercent: Double
    let apiUsedPercent: Double
    let fetchedAt: Date?
    let connectionState: CursorConnectionState

    static let disconnected = CursorUsageSnapshot(
        planLabel: "Cursor",
        totalUsedPercent: 0,
        autoUsedPercent: 0,
        apiUsedPercent: 0,
        fetchedAt: nil,
        connectionState: .disconnected
    )

    func withConnectionState(_ state: CursorConnectionState) -> CursorUsageSnapshot {
        CursorUsageSnapshot(
            planLabel: planLabel,
            totalUsedPercent: totalUsedPercent,
            autoUsedPercent: autoUsedPercent,
            apiUsedPercent: apiUsedPercent,
            fetchedAt: fetchedAt,
            connectionState: state
        )
    }
}

enum DashboardPresentationState: Equatable {
    case firstRun
    case dashboard
}

struct DashboardState: Equatable {
    let presentationState: DashboardPresentationState
    let cursorSnapshot: CursorUsageSnapshot
    let lastRefreshAt: Date?

    static let initial = DashboardState(
        presentationState: .firstRun,
        cursorSnapshot: .disconnected,
        lastRefreshAt: nil
    )
}

extension CursorUsageSnapshot {
    var hasSuccessfulSync: Bool {
        fetchedAt != nil
    }
}
