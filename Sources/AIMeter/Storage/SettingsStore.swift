import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            persist()
        }
    }

    private let userDefaults: UserDefaults
    private let storageKey = "aimeter.settings"
    private let legacyCursorStorageKey = "aimeter.cursor.settings"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded.mergedWithDefaults
        } else if
            let data = userDefaults.data(forKey: legacyCursorStorageKey),
            let decoded = try? JSONDecoder().decode(CursorSettings.self, from: data)
        {
            settings = AppSettings(
                pollIntervalSeconds: 300,
                hasCompletedInitialSetup: false,
                cursor: decoded.mergedWithDefaults,
                claude: .default
            )
        } else {
            settings = .default
        }
    }

    func setPollInterval(seconds: TimeInterval) {
        settings.pollIntervalSeconds = max(300, seconds)
    }

    func markInitialSetupComplete() {
        guard !settings.hasCompletedInitialSetup else {
            return
        }

        settings.hasCompletedInitialSetup = true
    }

    func setCursorUsagePageURL(_ url: String) {
        settings.cursor.usagePageURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setClaudeUsagePageURL(_ url: String) {
        settings.claude.usagePageURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(settings) else {
            return
        }

        userDefaults.set(encoded, forKey: storageKey)
    }
}

private extension AppSettings {
    var mergedWithDefaults: AppSettings {
        AppSettings(
            pollIntervalSeconds: max(300, pollIntervalSeconds),
            hasCompletedInitialSetup: hasCompletedInitialSetup,
            cursor: cursor.mergedWithDefaults,
            claude: claude.mergedWithDefaults
        )
    }
}

private extension CursorSettings {
    var mergedWithDefaults: CursorSettings {
        CursorSettings(
            usagePageURL: CursorURLValidator.sanitizedUsageURL(usagePageURL)
        )
    }
}

private extension ClaudeSettings {
    var mergedWithDefaults: ClaudeSettings {
        ClaudeSettings(
            usagePageURL: ClaudeURLValidator.sanitizedUsageURL(usagePageURL)
        )
    }
}
