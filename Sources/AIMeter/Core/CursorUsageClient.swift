import Foundation

@MainActor
protocol CursorUsageClient {
    func connect() async throws
    func fetchUsage() async throws -> CursorUsageSnapshot
    func disconnect()
}

enum CursorUsageError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case disconnected
    case authExpired
    case syncFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .disconnected:
            return "Cursor is not connected"
        case .authExpired:
            return "Cursor session expired. Reconnect to continue."
        case .syncFailed(let message):
            return message
        case .cancelled:
            return "Connection window closed before Cursor finished loading."
        }
    }

    var connectionState: CursorConnectionState {
        switch self {
        case .disconnected, .cancelled:
            return .disconnected
        case .authExpired:
            return .authExpired
        case .invalidConfiguration(let message), .syncFailed(let message):
            return .syncFailed(reason: message)
        }
    }
}
