import Foundation
import Combine

@MainActor
final class DashboardStore: ObservableObject {
    @Published private(set) var state: DashboardState = .initial

    private var cancellables: Set<AnyCancellable> = []
    private let settingsStore: SettingsStore

    init(
        settingsStore: SettingsStore,
        cursorUsageCoordinator: CursorUsageCoordinator
    ) {
        self.settingsStore = settingsStore

        cursorUsageCoordinator.$snapshot
            .sink { [weak self] cursorSnapshot in
                guard let self else { return }

                if !self.settingsStore.settings.hasCompletedInitialSetup,
                   cursorSnapshot.hasSuccessfulSync {
                    self.settingsStore.markInitialSetupComplete()
                }

                self.state = DashboardState(
                    presentationState: Self.presentationState(
                        settings: self.settingsStore.settings,
                        cursorSnapshot: cursorSnapshot
                    ),
                    cursorSnapshot: cursorSnapshot,
                    lastRefreshAt: cursorSnapshot.fetchedAt
                )
            }
            .store(in: &cancellables)
    }

    private static func presentationState(
        settings: AppSettings,
        cursorSnapshot: CursorUsageSnapshot
    ) -> DashboardPresentationState {
        if !settings.hasCompletedInitialSetup && !cursorSnapshot.hasSuccessfulSync {
            return .firstRun
        }

        return .dashboard
    }
}
