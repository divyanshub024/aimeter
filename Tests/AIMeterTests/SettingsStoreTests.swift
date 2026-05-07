import XCTest
@testable import AIMeter

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testInitialSetupCompletionPersistsAcrossReloads() {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let firstStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertFalse(firstStore.settings.hasCompletedInitialSetup)

        firstStore.markInitialSetupComplete()
        XCTAssertTrue(firstStore.settings.hasCompletedInitialSetup)

        let secondStore = SettingsStore(userDefaults: userDefaults)
        XCTAssertTrue(secondStore.settings.hasCompletedInitialSetup)
    }

    func testLegacyCursorSettingsDefaultToIncompleteOnboarding() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let legacyCursorSettings = CursorSettings(usagePageURL: "https://www.cursor.com/settings")
        let encoded = try JSONEncoder().encode(legacyCursorSettings)
        userDefaults.set(encoded, forKey: "aimeter.cursor.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertFalse(store.settings.hasCompletedInitialSetup)
        XCTAssertEqual(store.settings.cursor.usagePageURL, "https://www.cursor.com/settings")
    }

    func testInvalidLegacyCursorURLFallsBackToDefault() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let legacyCursorSettings = CursorSettings(usagePageURL: "file:///tmp/fake-cursor.html")
        let encoded = try JSONEncoder().encode(legacyCursorSettings)
        userDefaults.set(encoded, forKey: "aimeter.cursor.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.settings.cursor.usagePageURL, CursorSettings.default.usagePageURL)
    }

    func testExistingSettingsWithoutClaudeKeepCursorConfiguration() throws {
        let suiteName = #function
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let encoded = try JSONEncoder().encode(
            LegacyAppSettings(
                pollIntervalSeconds: 600,
                hasCompletedInitialSetup: true,
                cursor: CursorSettings(usagePageURL: "https://cursor.com/settings/account")
            )
        )
        userDefaults.set(encoded, forKey: "aimeter.settings")

        let store = SettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.settings.pollIntervalSeconds, 600)
        XCTAssertTrue(store.settings.hasCompletedInitialSetup)
        XCTAssertEqual(store.settings.cursor.usagePageURL, "https://cursor.com/settings/account")
        XCTAssertEqual(store.settings.claude, .default)
    }
}

private struct LegacyAppSettings: Codable {
    let pollIntervalSeconds: TimeInterval
    let hasCompletedInitialSetup: Bool
    let cursor: CursorSettings
}
