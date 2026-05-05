import Foundation

@MainActor
final class CursorUsageCoordinator: ObservableObject {
    @Published private(set) var snapshot: CursorUsageSnapshot = .disconnected
    @Published private(set) var isRefreshing = false
    @Published private(set) var isConnecting = false

    private let settingsStore: SettingsStore
    private let client: CursorUsageClient

    private var refreshTask: Task<Void, Never>?
    private var lastSuccessfulSnapshot: CursorUsageSnapshot?

    init(settingsStore: SettingsStore, client: CursorUsageClient) {
        self.settingsStore = settingsStore
        self.client = client
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
            await refresh()
        } catch let error as CursorUsageError {
            applyFailureState(error.connectionState)
        } catch {
            applyFailureState(.syncFailed(reason: error.localizedDescription))
        }
    }

    func disconnect() {
        client.disconnect()
        lastSuccessfulSnapshot = nil
        snapshot = .disconnected
    }

    func refresh() async {
        if isRefreshing || isConnecting {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fetched = try await client.fetchUsage()
            snapshot = fetched
            lastSuccessfulSnapshot = fetched
        } catch let error as CursorUsageError {
            applyFailureState(error.connectionState)
        } catch {
            applyFailureState(.syncFailed(reason: error.localizedDescription))
        }
    }

    private func applyFailureState(_ state: CursorConnectionState) {
        if let lastSuccessfulSnapshot {
            snapshot = lastSuccessfulSnapshot.withConnectionState(state)
        } else {
            snapshot = CursorUsageSnapshot.disconnected.withConnectionState(state)
        }
    }
}
