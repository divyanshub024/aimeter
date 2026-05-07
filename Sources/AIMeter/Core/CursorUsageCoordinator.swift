import Foundation

@MainActor
final class ProviderUsageCoordinator: ObservableObject {
    @Published private(set) var snapshot: ProviderUsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var isConnecting = false
    @Published private(set) var hasLoadedOnce = false

    let provider: UsageProvider

    private let settingsStore: SettingsStore
    private let client: ProviderUsageClient

    private var refreshTask: Task<Void, Never>?
    private var lastSuccessfulSnapshot: ProviderUsageSnapshot?

    init(settingsStore: SettingsStore, client: ProviderUsageClient) {
        self.settingsStore = settingsStore
        self.client = client
        self.provider = client.provider
        self.snapshot = DashboardState.defaultSnapshot(for: client.provider)
    }

    func start() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                let interval = max(300, self.settingsStore.settings.pollIntervalSeconds)
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                if Task.isCancelled {
                    return
                }
                await self.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func connect() async {
        if isConnecting {
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            try await client.connect()
            try await fetchAndStoreSnapshot()
            hasLoadedOnce = true
        } catch let error as ProviderUsageError {
            applyFailureState(error.connectionState)
            hasLoadedOnce = true
        } catch {
            applyFailureState(.syncFailed(reason: error.localizedDescription))
            hasLoadedOnce = true
        }
    }

    func disconnect() {
        client.disconnect()
        lastSuccessfulSnapshot = nil
        snapshot = DashboardState.defaultSnapshot(for: provider)
    }

    func refresh() async {
        if isRefreshing || isConnecting {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoadedOnce = true
        }

        do {
            try await fetchAndStoreSnapshot()
        } catch let error as ProviderUsageError {
            applyFailureState(error.connectionState)
        } catch {
            applyFailureState(.syncFailed(reason: error.localizedDescription))
        }
    }

    private func fetchAndStoreSnapshot() async throws {
        let fetched = try await client.fetchUsage()
        snapshot = fetched
        lastSuccessfulSnapshot = fetched
    }

    private func applyFailureState(_ state: ProviderConnectionState) {
        if let lastSuccessfulSnapshot {
            snapshot = lastSuccessfulSnapshot.withConnectionState(state)
        } else {
            snapshot = DashboardState.defaultSnapshot(for: provider).withConnectionState(state)
        }
    }
}

typealias CursorUsageCoordinator = ProviderUsageCoordinator
typealias ClaudeUsageCoordinator = ProviderUsageCoordinator
