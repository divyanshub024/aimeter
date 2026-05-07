import SwiftUI

struct MenuPopoverView: View {
    @ObservedObject var dashboardStore: DashboardStore
    @ObservedObject var cursorUsageCoordinator: CursorUsageCoordinator
    @ObservedObject var claudeUsageCoordinator: ClaudeUsageCoordinator

    let onRefreshCursor: () -> Void
    let onRefreshClaude: () -> Void
    let onConnectCursor: () -> Void
    let onConnectClaude: () -> Void
    let onDisconnectCursor: () -> Void
    let onDisconnectClaude: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let state = dashboardStore.state
        let connectedSnapshots = state.connectedProviderSnapshots
        let popoverHeight = preferredHeight(
            state: state,
            connectedProviderCount: connectedSnapshots.count
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()

                if shouldShowInitialLoading(state: state, connectedProviderCount: connectedSnapshots.count) {
                    initialLoadingContent
                } else if state.presentationState == .firstRun || connectedSnapshots.isEmpty {
                    firstRunContent
                } else {
                    ForEach(connectedSnapshots, id: \.provider) { snapshot in
                        providerSection(snapshot)
                    }
                    Divider()
                    footer(state)
                }
            }
            .padding(14)
        }
        .frame(width: 380, height: popoverHeight, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AIMeter")
                    .font(.headline)
                Spacer()
                if isAnyProviderBusy {
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
                Text("Track Cursor and Claude usage from signed-in local web sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isAnyProviderBusy: Bool {
        cursorUsageCoordinator.isRefreshing ||
            cursorUsageCoordinator.isConnecting ||
            claudeUsageCoordinator.isRefreshing ||
            claudeUsageCoordinator.isConnecting
    }

    private var isAnyProviderConnecting: Bool {
        cursorUsageCoordinator.isConnecting || claudeUsageCoordinator.isConnecting
    }

    private var isAnyProviderRefreshing: Bool {
        cursorUsageCoordinator.isRefreshing || claudeUsageCoordinator.isRefreshing
    }

    private var hasLoadedProviderState: Bool {
        cursorUsageCoordinator.hasLoadedOnce && claudeUsageCoordinator.hasLoadedOnce
    }

    private func shouldShowInitialLoading(
        state: DashboardState,
        connectedProviderCount: Int
    ) -> Bool {
        state.presentationState == .firstRun &&
            connectedProviderCount == 0 &&
            (isAnyProviderRefreshing || !hasLoadedProviderState) &&
            !isAnyProviderConnecting
    }

    private func preferredHeight(
        state: DashboardState,
        connectedProviderCount: Int
    ) -> CGFloat {
        if state.presentationState == .firstRun || connectedProviderCount == 0 {
            return 420
        }

        return connectedProviderCount == 1 ? 370 : 560
    }

    private var firstRunContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connect a Provider")
                    .font(.title3.weight(.semibold))
                Text("AIMeter reads usage from signed-in provider pages. No API key is required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            onboardingTile(
                description: "Track total plan usage, Auto usage, and API usage from your Cursor settings dashboard.",
                buttonTitle: "Connect Cursor",
                action: onConnectCursor
            )

            onboardingTile(
                provider: .claude,
                description: "Track Claude usage, limits, and reset information when Claude exposes it in your account session.",
                buttonTitle: "Connect Claude",
                action: onConnectClaude
            )

            HStack {
                Spacer()
                Button("Quit", action: onQuit)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var initialLoadingContent: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 76)
            ProgressView()
                .controlSize(.regular)
            Text("Checking connected sessions...")
                .font(.headline)
            Text("AIMeter is loading saved Cursor and Claude sessions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 76)
        }
        .frame(maxWidth: .infinity)
    }

    private func providerSection(_ snapshot: ProviderUsageSnapshot) -> some View {
        let statusMetrics = snapshot.secondaryMetrics.filter { $0.percent == nil }
        let usageMetrics = snapshot.secondaryMetrics.filter { $0.percent != nil }
        let primaryResetText = primaryResetText(for: snapshot, statusMetrics: statusMetrics)
        let unpairedStatusMetrics = unpairedStatusMetrics(
            statusMetrics,
            snapshot: snapshot,
            usageMetrics: usageMetrics
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snapshot.planLabel)
                        .font(.title3.weight(.semibold))
                    Text(snapshot.connectionState.displayText)
                        .font(.caption)
                        .foregroundStyle(providerStatusColor(for: snapshot.connectionState))
                }
                Spacer()
                Text(snapshot.primaryMetric.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }

            if let progressPercent = snapshot.progressPercent {
                ProgressView(value: progressPercent / 100)
                    .tint(providerProgressColor(for: progressPercent))
            }

            if let primaryResetText {
                Text(primaryResetText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !unpairedStatusMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(unpairedStatusMetrics, id: \.title) { metric in
                        statusMetricLine(metric)
                    }
                }
            }

            if !usageMetrics.isEmpty {
                HStack(spacing: 10) {
                    ForEach(usageMetrics, id: \.title) { metric in
                        metricCard(
                            title: metric.title,
                            value: metric.value,
                            subtitle: resetText(for: metric, statusMetrics: statusMetrics)
                        )
                    }
                }
            }

            providerFooter(
                lastSync: snapshot.fetchedAt,
                message: providerMessage(for: snapshot)
            )

            HStack {
                Button("Refresh", action: actions(for: snapshot.provider).refresh)
                    .buttonStyle(.bordered)
                    .disabled(coordinator(for: snapshot.provider).isRefreshing || coordinator(for: snapshot.provider).isConnecting)

                Button(connectButtonTitle(for: snapshot), action: actions(for: snapshot.provider).connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(coordinator(for: snapshot.provider).isConnecting)

                Button("Disconnect", action: actions(for: snapshot.provider).disconnect)
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

    private func statusMetricLine(_ metric: UsageMetric) -> some View {
        HStack(spacing: 6) {
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func primaryResetText(
        for snapshot: ProviderUsageSnapshot,
        statusMetrics: [UsageMetric]
    ) -> String? {
        statusMetrics.first { metric in
            metric.title.caseInsensitiveCompare("Reset") == .orderedSame ||
                metric.title.caseInsensitiveCompare("\(snapshot.primaryMetric.title) reset") == .orderedSame
        }?.value
    }

    private func resetText(
        for usageMetric: UsageMetric,
        statusMetrics: [UsageMetric]
    ) -> String? {
        statusMetrics.first { metric in
            metric.title.caseInsensitiveCompare("\(usageMetric.title) reset") == .orderedSame
        }?.value
    }

    private func unpairedStatusMetrics(
        _ statusMetrics: [UsageMetric],
        snapshot: ProviderUsageSnapshot,
        usageMetrics: [UsageMetric]
    ) -> [UsageMetric] {
        statusMetrics.filter { metric in
            if metric.title.caseInsensitiveCompare("Reset") == .orderedSame ||
                metric.title.caseInsensitiveCompare("\(snapshot.primaryMetric.title) reset") == .orderedSame {
                return false
            }

            return !usageMetrics.contains { usageMetric in
                metric.title.caseInsensitiveCompare("\(usageMetric.title) reset") == .orderedSame
            }
        }
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
        provider: UsageProvider = .cursor,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(provider == .cursor ? Color.blue : Color.purple)
                    .frame(width: 8, height: 8)
                Text(provider.displayName)
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

    private func metricCard(title: String, value: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(2)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private func connectButtonTitle(for snapshot: ProviderUsageSnapshot) -> String {
        switch snapshot.connectionState {
        case .connected:
            return "Reconnect"
        case .disconnected, .authExpired, .syncFailed:
            return "Connect \(snapshot.provider.displayName)"
        }
    }

    private func providerMessage(for snapshot: ProviderUsageSnapshot) -> String? {
        switch snapshot.connectionState {
        case .connected:
            return nil
        case .authExpired:
            return "Reconnect \(snapshot.provider.displayName) to refresh usage."
        case .disconnected:
            return "Connect \(snapshot.provider.displayName) to start tracking usage."
        case .syncFailed(let reason):
            return reason
        }
    }

    private func providerProgressColor(for percent: Double) -> Color {
        switch percent {
        case 90...:
            return .red
        case 70...:
            return .orange
        default:
            return .blue
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

    private func coordinator(for provider: UsageProvider) -> ProviderUsageCoordinator {
        switch provider {
        case .cursor:
            return cursorUsageCoordinator
        case .claude:
            return claudeUsageCoordinator
        }
    }

    private func actions(for provider: UsageProvider) -> (refresh: () -> Void, connect: () -> Void, disconnect: () -> Void) {
        switch provider {
        case .cursor:
            return (onRefreshCursor, onConnectCursor, onDisconnectCursor)
        case .claude:
            return (onRefreshClaude, onConnectClaude, onDisconnectClaude)
        }
    }
}
