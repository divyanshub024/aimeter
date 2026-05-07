import Foundation
import WebKit

@MainActor
protocol ClaudeSessionManaging {
    func connect(to usagePageURL: URL) async throws -> ProviderUsageSnapshot
    func fetchUsage(from usagePageURL: URL) async throws -> ProviderUsageSnapshot
    func disconnect()
}

@MainActor
final class ClaudeSessionManager: ClaudeSessionManaging {
    private static let dataStoreIdentifier = UUID(uuidString: "B724E326-3580-4AC5-9C85-BF51F3E5A3A1")!

    private let dataStore: WKWebsiteDataStore
    private var connectionWindowController: UsageConnectionWindowController?
    private var activeScraper: ClaudeWebViewScraper?

    private(set) var isConnected = false

    init() {
        self.dataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreIdentifier)
    }

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
    }

    func connect(to usagePageURL: URL) async throws -> ProviderUsageSnapshot {
        let scraper = ClaudeWebViewScraper(mode: .interactive, usagePageURL: usagePageURL, dataStore: dataStore)
        let windowController = UsageConnectionWindowController(title: "Connect Claude", webView: scraper.webView)

        activeScraper = scraper
        connectionWindowController = windowController
        windowController.onClose = { [weak scraper] in
            scraper?.cancel()
        }
        windowController.show()

        defer {
            activeScraper = nil
            connectionWindowController = nil
        }

        do {
            let snapshot = try await scraper.start()
            isConnected = true
            windowController.close()
            return snapshot
        } catch {
            throw error
        }
    }

    func fetchUsage(from usagePageURL: URL) async throws -> ProviderUsageSnapshot {
        let scraper = ClaudeWebViewScraper(mode: .background, usagePageURL: usagePageURL, dataStore: dataStore)
        activeScraper = scraper
        defer { activeScraper = nil }
        let snapshot = try await scraper.start()
        isConnected = true
        return snapshot
    }

    func disconnect() {
        isConnected = false
        activeScraper?.cancel()
        connectionWindowController?.close()
        clearWebsiteData()
    }

    private func clearWebsiteData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { [dataStore] records in
            let claudeRecords = records.filter { record in
                record.displayName.localizedCaseInsensitiveContains("claude")
            }
            dataStore.removeData(ofTypes: types, for: claudeRecords) {}
        }
    }
}
