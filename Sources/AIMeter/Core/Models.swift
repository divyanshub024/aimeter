import Foundation

struct AppSettings: Codable, Equatable {
    var pollIntervalSeconds: TimeInterval
    var hasCompletedInitialSetup: Bool
    var cursor: CursorSettings
    var claude: ClaudeSettings

    private enum CodingKeys: String, CodingKey {
        case pollIntervalSeconds
        case hasCompletedInitialSetup
        case cursor
        case claude
    }

    init(
        pollIntervalSeconds: TimeInterval,
        hasCompletedInitialSetup: Bool,
        cursor: CursorSettings,
        claude: ClaudeSettings
    ) {
        self.pollIntervalSeconds = pollIntervalSeconds
        self.hasCompletedInitialSetup = hasCompletedInitialSetup
        self.cursor = cursor
        self.claude = claude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        pollIntervalSeconds = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .pollIntervalSeconds
        ) ?? Self.default.pollIntervalSeconds
        hasCompletedInitialSetup = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedInitialSetup
        ) ?? Self.default.hasCompletedInitialSetup
        cursor = try container.decodeIfPresent(CursorSettings.self, forKey: .cursor) ?? .default
        claude = try container.decodeIfPresent(ClaudeSettings.self, forKey: .claude) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pollIntervalSeconds, forKey: .pollIntervalSeconds)
        try container.encode(hasCompletedInitialSetup, forKey: .hasCompletedInitialSetup)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(claude, forKey: .claude)
    }

    static let `default` = AppSettings(
        pollIntervalSeconds: 300,
        hasCompletedInitialSetup: false,
        cursor: .default,
        claude: .default
    )
}

struct CursorSettings: Codable, Equatable {
    var usagePageURL: String

    static let `default` = CursorSettings(
        usagePageURL: "https://www.cursor.com/settings"
    )
}

struct ClaudeSettings: Codable, Equatable {
    var usagePageURL: String

    static let `default` = ClaudeSettings(
        usagePageURL: "https://claude.ai/settings/usage"
    )
}

enum UsageProvider: String, CaseIterable, Codable, Equatable {
    case cursor
    case claude

    var displayName: String {
        switch self {
        case .cursor:
            return "Cursor"
        case .claude:
            return "Claude"
        }
    }
}

enum ProviderConnectionState: Equatable {
    case disconnected
    case connected
    case authExpired
    case syncFailed(reason: String)

    var displayText: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connected:
            return "Connected"
        case .authExpired:
            return "Session expired"
        case .syncFailed(let reason):
            return reason
        }
    }
}

typealias CursorConnectionState = ProviderConnectionState

struct UsageMetric: Equatable {
    let title: String
    let value: String
    let percent: Double?

    init(title: String, value: String, percent: Double? = nil) {
        self.title = title
        self.value = value
        self.percent = percent.map { min(max($0, 0), 100) }
    }
}

struct ProviderUsageSnapshot: Equatable {
    let provider: UsageProvider
    let planLabel: String
    let primaryMetric: UsageMetric
    let secondaryMetrics: [UsageMetric]
    let fetchedAt: Date?
    let connectionState: ProviderConnectionState

    static let disconnected = ProviderUsageSnapshot.cursorDisconnected

    static let cursorDisconnected = ProviderUsageSnapshot(
        provider: .cursor,
        planLabel: "Cursor",
        primaryMetric: UsageMetric(title: "Total", value: DisplayFormatting.percent(0), percent: 0),
        secondaryMetrics: [
            UsageMetric(title: "Auto", value: DisplayFormatting.percent(0), percent: 0),
            UsageMetric(title: "API", value: DisplayFormatting.percent(0), percent: 0)
        ],
        fetchedAt: nil,
        connectionState: .disconnected
    )

    static let claudeDisconnected = ProviderUsageSnapshot(
        provider: .claude,
        planLabel: "Claude",
        primaryMetric: UsageMetric(title: "Usage", value: "Not connected"),
        secondaryMetrics: [],
        fetchedAt: nil,
        connectionState: .disconnected
    )

    init(
        provider: UsageProvider,
        planLabel: String,
        primaryMetric: UsageMetric,
        secondaryMetrics: [UsageMetric],
        fetchedAt: Date?,
        connectionState: ProviderConnectionState
    ) {
        self.provider = provider
        self.planLabel = planLabel
        self.primaryMetric = primaryMetric
        self.secondaryMetrics = secondaryMetrics
        self.fetchedAt = fetchedAt
        self.connectionState = connectionState
    }

    init(
        planLabel: String,
        totalUsedPercent: Double,
        autoUsedPercent: Double,
        apiUsedPercent: Double,
        fetchedAt: Date?,
        connectionState: ProviderConnectionState
    ) {
        self.init(
            provider: .cursor,
            planLabel: planLabel,
            primaryMetric: UsageMetric(
                title: "Total",
                value: DisplayFormatting.percent(totalUsedPercent),
                percent: totalUsedPercent
            ),
            secondaryMetrics: [
                UsageMetric(title: "Auto", value: DisplayFormatting.percent(autoUsedPercent), percent: autoUsedPercent),
                UsageMetric(title: "API", value: DisplayFormatting.percent(apiUsedPercent), percent: apiUsedPercent)
            ],
            fetchedAt: fetchedAt,
            connectionState: connectionState
        )
    }

    var progressPercent: Double? {
        primaryMetric.percent
    }

    var totalUsedPercent: Double {
        progressPercent ?? 0
    }

    var autoUsedPercent: Double {
        metricPercent(named: "Auto")
    }

    var apiUsedPercent: Double {
        metricPercent(named: "API")
    }

    func withConnectionState(_ state: ProviderConnectionState) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            provider: provider,
            planLabel: planLabel,
            primaryMetric: primaryMetric,
            secondaryMetrics: secondaryMetrics,
            fetchedAt: fetchedAt,
            connectionState: state
        )
    }

    private func metricPercent(named title: String) -> Double {
        secondaryMetrics.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }?.percent ?? 0
    }
}

typealias CursorUsageSnapshot = ProviderUsageSnapshot

enum DashboardPresentationState: Equatable {
    case firstRun
    case dashboard
}

struct DashboardState: Equatable {
    let presentationState: DashboardPresentationState
    let providerSnapshots: [ProviderUsageSnapshot]
    let lastRefreshAt: Date?

    static let initial = DashboardState(
        presentationState: .firstRun,
        providerSnapshots: [.cursorDisconnected, .claudeDisconnected],
        lastRefreshAt: nil
    )

    var cursorSnapshot: ProviderUsageSnapshot {
        snapshot(for: .cursor)
    }

    var claudeSnapshot: ProviderUsageSnapshot {
        snapshot(for: .claude)
    }

    var connectedProviderSnapshots: [ProviderUsageSnapshot] {
        providerSnapshots.filter { $0.connectionState == .connected }
    }

    var menuBarProgressPercent: Double {
        connectedProviderSnapshots.compactMap(\.progressPercent).max() ?? 0
    }

    private func snapshot(for provider: UsageProvider) -> ProviderUsageSnapshot {
        providerSnapshots.first { $0.provider == provider } ?? Self.defaultSnapshot(for: provider)
    }

    static func defaultSnapshot(for provider: UsageProvider) -> ProviderUsageSnapshot {
        switch provider {
        case .cursor:
            return .cursorDisconnected
        case .claude:
            return .claudeDisconnected
        }
    }
}

extension ProviderUsageSnapshot {
    var hasSuccessfulSync: Bool {
        fetchedAt != nil
    }
}
