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
    private var operationGeneration = 0
    private var isManuallyDisconnected = false

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

        isManuallyDisconnected = false
        operationGeneration += 1
        let generation = operationGeneration
        isConnecting = true
        defer { isConnecting = false }

        do {
            try await client.connect()
            try await fetchAndStoreSnapshot(generation: generation)
            guard generation == operationGeneration else { return }
            hasLoadedOnce = true
        } catch let error as ProviderUsageError {
            guard generation == operationGeneration else { return }
            applyFailureState(error.connectionState)
            hasLoadedOnce = true
        } catch {
            guard generation == operationGeneration else { return }
            applyFailureState(.syncFailed(reason: error.localizedDescription))
            hasLoadedOnce = true
        }
    }

    func disconnect() {
        operationGeneration += 1
        isManuallyDisconnected = true
        client.disconnect()
        lastSuccessfulSnapshot = nil
        snapshot = DashboardState.defaultSnapshot(for: provider)
        hasLoadedOnce = true
    }

    func refresh() async {
        if isRefreshing || isConnecting || isManuallyDisconnected {
            return
        }

        let generation = operationGeneration
        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoadedOnce = true
        }

        do {
            try await fetchAndStoreSnapshot(generation: generation)
        } catch let error as ProviderUsageError {
            guard generation == operationGeneration else { return }
            applyFailureState(error.connectionState)
        } catch {
            guard generation == operationGeneration else { return }
            applyFailureState(.syncFailed(reason: error.localizedDescription))
        }
    }

    private func fetchAndStoreSnapshot(generation: Int) async throws {
        let fetched = try await client.fetchUsage()
        guard generation == operationGeneration else { return }
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
