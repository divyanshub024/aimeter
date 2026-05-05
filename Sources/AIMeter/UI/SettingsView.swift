import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var dashboardStore: DashboardStore
    @ObservedObject var cursorUsageCoordinator: CursorUsageCoordinator

    var body: some View {
        let state = dashboardStore.state

        Form {
            Section("Cursor") {
                connectionStatusRow(
                    title: "Status",
                    value: state.cursorSnapshot.connectionState.displayText,
                    color: cursorStatusColor(for: state.cursorSnapshot.connectionState)
                )

                connectionStatusRow(
                    title: "Last sync",
                    value: DisplayFormatting.relativeTimestamp(state.cursorSnapshot.fetchedAt),
                    color: .secondary
                )

                HStack(spacing: 10) {
                    Button(cursorConnectButtonTitle(for: state.cursorSnapshot)) {
                        Task { await cursorUsageCoordinator.connect() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cursorUsageCoordinator.isConnecting)

                    Button("Disconnect") {
                        cursorUsageCoordinator.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.cursorSnapshot.connectionState == .disconnected)
                }

                Text("AIMeter uses a local Cursor web session stored in this app. No API key is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .frame(minWidth: 520, minHeight: 320)
        .padding(12)
    }

    private var pollIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { settingsStore.settings.pollIntervalSeconds },
            set: { settingsStore.setPollInterval(seconds: $0) }
        )
    }

    private func connectionStatusRow(title: String, value: String, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(color)
        }
    }

    private func cursorConnectButtonTitle(for snapshot: CursorUsageSnapshot) -> String {
        switch snapshot.connectionState {
        case .connected:
            return "Reconnect Cursor"
        case .disconnected, .authExpired, .syncFailed:
            return "Connect Cursor"
        }
    }

    private func cursorStatusColor(for state: CursorConnectionState) -> Color {
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
