import Foundation
import Combine

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var state: DashboardState = .initial

    private var cancellables: Set<AnyCancellable> = []
    private let settingsStore: SettingsStore
    private var snapshotsByProvider: [UsageProvider: ProviderUsageSnapshot] = [:]

    init(
        settingsStore: SettingsStore,
        cursorUsageCoordinator: CursorUsageCoordinator,
        claudeUsageCoordinator: ClaudeUsageCoordinator? = nil
    ) {
        self.settingsStore = settingsStore

        let coordinators = [cursorUsageCoordinator, claudeUsageCoordinator].compactMap { $0 }
        for coordinator in coordinators {
            snapshotsByProvider[coordinator.provider] = coordinator.snapshot

            coordinator.$snapshot
                .sink { [weak self] snapshot in
                    self?.update(snapshot)
                }
                .store(in: &cancellables)
        }

        publishState()
    }

    private func update(_ snapshot: ProviderUsageSnapshot) {
        snapshotsByProvider[snapshot.provider] = snapshot

        if !settingsStore.settings.hasCompletedInitialSetup,
           snapshotsByProvider.values.contains(where: \.hasSuccessfulSync) {
            settingsStore.markInitialSetupComplete()
        }

        publishState()
    }

    private func publishState() {
        let snapshots = UsageProvider.allCases.map { provider in
            snapshotsByProvider[provider] ?? DashboardState.defaultSnapshot(for: provider)
        }

        state = DashboardState(
            presentationState: Self.presentationState(
                settings: settingsStore.settings,
                snapshots: snapshots
            ),
            providerSnapshots: snapshots,
            lastRefreshAt: snapshots.compactMap(\.fetchedAt).max()
        )
    }

    private static func presentationState(settings: AppSettings, snapshots: [ProviderUsageSnapshot]) -> DashboardPresentationState {
        if !settings.hasCompletedInitialSetup && !snapshots.contains(where: \.hasSuccessfulSync) {
            return .firstRun
        }

        return .dashboard
    }
}
