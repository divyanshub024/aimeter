import Foundation

@MainActor
final class CursorDashboardClient: CursorUsageClient {
    private let settingsStore: SettingsStore
    private let sessionManager: CursorSessionManaging
    private var pendingConnectedSnapshot: CursorUsageSnapshot?

    init(settingsStore: SettingsStore, sessionManager: CursorSessionManaging) {
        self.settingsStore = settingsStore
        self.sessionManager = sessionManager
    }

    func connect() async throws {
        let usagePageURL = try resolvedUsagePageURL()
        pendingConnectedSnapshot = try await sessionManager.connect(to: usagePageURL)
    }

    func fetchUsage() async throws -> CursorUsageSnapshot {
        if let pendingConnectedSnapshot {
            self.pendingConnectedSnapshot = nil
            return pendingConnectedSnapshot
        }

        let usagePageURL = try resolvedUsagePageURL()
        return try await sessionManager.fetchUsage(from: usagePageURL)
    }

    func disconnect() {
        pendingConnectedSnapshot = nil
        sessionManager.disconnect()
    }

    private func resolvedUsagePageURL() throws -> URL {
        try CursorURLValidator.validatedUsageURL(from: settingsStore.settings.cursor.usagePageURL)
    }
}
