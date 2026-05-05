import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var dashboardStore: DashboardStore
    @ObservedObject var cursorUsageCoordinator: CursorUsageCoordinator

    let onRefreshCursor: () -> Void
    let onConnectCursor: () -> Void
    let onDisconnectCursor: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let state = dashboardStore.state

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()

                if state.presentationState == .firstRun {
                    firstRunContent
                } else {
                    cursorSection(state.cursorSnapshot)
                    Divider()
                    footer(state)
                }
            }
            .padding(14)
            .padding(.bottom, 2)
        }
        .frame(width: 360, height: 370, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AIMeter")
                    .font(.headline)
                Spacer()
                if cursorUsageCoordinator.isRefreshing || cursorUsageCoordinator.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }

            if dashboardStore.state.presentationState == .firstRun {
                Text("Track Cursor usage from your signed-in web session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var firstRunContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect Cursor")
                    .font(.title3.weight(.semibold))
                Text("AIMeter reads usage from your signed-in Cursor settings dashboard. No API key is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            onboardingTile(
                description: "Track total plan usage, Auto usage, and API usage from your Cursor settings dashboard.",
                buttonTitle: "Connect Cursor",
                action: onConnectCursor
            )

            HStack {
                Spacer()
                Button("Quit", action: onQuit)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func cursorSection(_ snapshot: CursorUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cursor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snapshot.planLabel)
                        .font(.title3.weight(.semibold))
                    Text(snapshot.connectionState.displayText)
                        .font(.caption)
                        .foregroundStyle(cursorStatusColor(for: snapshot.connectionState))
                }
                Spacer()
                Text(DisplayFormatting.percent(snapshot.totalUsedPercent))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            ProgressView(value: snapshot.totalUsedPercent / 100)
                .tint(cursorProgressColor(for: snapshot.totalUsedPercent))

            HStack(spacing: 10) {
                metricCard(title: "Auto", value: DisplayFormatting.percent(snapshot.autoUsedPercent))
                metricCard(title: "API", value: DisplayFormatting.percent(snapshot.apiUsedPercent))
            }

            providerFooter(
                lastSync: snapshot.fetchedAt,
                message: cursorMessage(for: snapshot.connectionState)
            )

            HStack {
                Button("Refresh", action: onRefreshCursor)
                    .buttonStyle(.bordered)
                    .disabled(cursorUsageCoordinator.isRefreshing || cursorUsageCoordinator.isConnecting)

                Button(cursorConnectButtonTitle(for: snapshot), action: onConnectCursor)
                    .buttonStyle(.borderedProminent)
                    .disabled(cursorUsageCoordinator.isConnecting)

                Button("Disconnect", action: onDisconnectCursor)
                    .buttonStyle(.bordered)
                    .disabled(snapshot.connectionState == .disconnected)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func footer(_ state: DashboardState) -> some View {
        HStack {
            Text("Last dashboard sync: \(DisplayFormatting.relativeTimestamp(state.lastRefreshAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit", action: onQuit)
                .buttonStyle(.bordered)
        }
    }

    private func onboardingTile(
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                Text("Cursor")
                    .font(.headline)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private func providerFooter(lastSync: Date?, message: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last sync: \(DisplayFormatting.relativeTimestamp(lastSync))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
    }

    private func cursorConnectButtonTitle(for snapshot: CursorUsageSnapshot) -> String {
        switch snapshot.connectionState {
        case .connected:
            return "Reconnect"
        case .disconnected, .authExpired, .syncFailed:
            return "Connect Cursor"
        }
    }

    private func cursorMessage(for state: CursorConnectionState) -> String? {
        switch state {
        case .connected:
            return nil
        case .authExpired:
            return "Reconnect Cursor to refresh the dashboard."
        case .disconnected:
            return "Connect your Cursor account to start tracking usage."
        case .syncFailed(let reason):
            return reason
        }
    }

    private func cursorProgressColor(for percent: Double) -> Color {
        switch percent {
        case 90...:
            return .red
        case 70...:
            return .orange
        default:
            return .blue
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
