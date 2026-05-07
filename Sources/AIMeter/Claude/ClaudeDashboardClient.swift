import Foundation

@MainActor
final class ClaudeDashboardClient: ProviderUsageClient {
    let provider = UsageProvider.claude

    private let settingsStore: SettingsStore
    private let sessionManager: ClaudeSessionManaging
    private var pendingConnectedSnapshot: ProviderUsageSnapshot?

    init(settingsStore: SettingsStore, sessionManager: ClaudeSessionManaging) {
        self.settingsStore = settingsStore
        self.sessionManager = sessionManager
    }

    func connect() async throws {
        let usagePageURL = try resolvedUsagePageURL()
        pendingConnectedSnapshot = try await sessionManager.connect(to: usagePageURL)
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        if let pendingConnectedSnapshot {
            self.pendingConnectedSnapshot = nil
            if pendingConnectedSnapshot.progressPercent != nil {
                return pendingConnectedSnapshot
            }
        }

        let usagePageURL = try resolvedUsagePageURL()
        return try await sessionManager.fetchUsage(from: usagePageURL)
    }

    func disconnect() {
        pendingConnectedSnapshot = nil
        sessionManager.disconnect()
    }

    private func resolvedUsagePageURL() throws -> URL {
        try ClaudeURLValidator.validatedUsageURL(from: settingsStore.settings.claude.usagePageURL)
    }
}
