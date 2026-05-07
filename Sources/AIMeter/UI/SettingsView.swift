import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var dashboardStore: DashboardStore
    @ObservedObject var cursorUsageCoordinator: CursorUsageCoordinator
    @ObservedObject var claudeUsageCoordinator: ClaudeUsageCoordinator
    @ObservedObject var launchAtLoginController: LaunchAtLoginController

    var body: some View {
        let state = dashboardStore.state

        Form {
            Section("General") {
                Toggle("Start AIMeter at login", isOn: launchAtLoginBinding)

                Text("Open AIMeter automatically when you sign in to macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let statusMessage = launchAtLoginController.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            providerSettingsSection(
                snapshot: state.cursorSnapshot,
                coordinator: cursorUsageCoordinator,
                localSessionDescription: "AIMeter uses a local Cursor web session stored in this app. No API key is required."
            )

            providerSettingsSection(
                snapshot: state.claudeSnapshot,
                coordinator: claudeUsageCoordinator,
                localSessionDescription: "AIMeter uses a local Claude web session stored in this app. No API key is required."
            )

            Section("Polling") {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Stepper(value: pollIntervalBinding, in: 300...1800, step: 60) {
                        Text("\(Int(settingsStore.settings.pollIntervalSeconds / 60)) min")
                            .monospacedDigit()
                    }
                    .frame(width: 160)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 520)
        .padding(12)
        .onAppear {
            launchAtLoginController.refresh()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginController.isEnabled },
            set: { launchAtLoginController.setEnabled($0) }
        )
    }

    private var pollIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { settingsStore.settings.pollIntervalSeconds },
            set: { settingsStore.setPollInterval(seconds: $0) }
        )
    }

    private func providerSettingsSection(
        snapshot: ProviderUsageSnapshot,
        coordinator: ProviderUsageCoordinator,
        localSessionDescription: String
    ) -> some View {
        Section(snapshot.provider.displayName) {
            connectionStatusRow(
                title: "Status",
                value: snapshot.connectionState.displayText,
                color: providerStatusColor(for: snapshot.connectionState)
            )

            connectionStatusRow(
                title: "Last sync",
                value: DisplayFormatting.relativeTimestamp(snapshot.fetchedAt),
                color: .secondary
            )

            HStack(spacing: 10) {
                Button(connectButtonTitle(for: snapshot)) {
                    Task { await coordinator.connect() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isConnecting)

                Button("Disconnect") {
                    coordinator.disconnect()
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.connectionState == .disconnected)
            }

            Text(localSessionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func connectionStatusRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(color)
        }
    }

    private func connectButtonTitle(for snapshot: ProviderUsageSnapshot) -> String {
        switch snapshot.connectionState {
        case .connected:
            return "Reconnect \(snapshot.provider.displayName)"
        case .disconnected, .authExpired, .syncFailed:
            return "Connect \(snapshot.provider.displayName)"
        }
    }

    private func providerStatusColor(for state: ProviderConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        case .authExpired, .syncFailed:
            return .orange
        }
    }
}
