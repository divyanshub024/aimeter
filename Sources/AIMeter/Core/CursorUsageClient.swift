import Foundation

@MainActor
protocol ProviderUsageClient {
    var provider: UsageProvider { get }
    func connect() async throws
    func fetchUsage() async throws -> ProviderUsageSnapshot
    func disconnect()
}

typealias CursorUsageClient = ProviderUsageClient

enum ProviderUsageError: LocalizedError, Equatable {
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
            return "Provider is not connected"
        case .authExpired:
            return "Session expired. Reconnect to continue."
        case .syncFailed(let message):
            return message
        case .cancelled:
            return "Connection window closed before the provider finished loading."
        }
    }

    var connectionState: ProviderConnectionState {
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

typealias CursorUsageError = ProviderUsageError
