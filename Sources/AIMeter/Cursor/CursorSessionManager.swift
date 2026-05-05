import Foundation
import WebKit

@MainActor
protocol CursorSessionManaging {
    func connect(to usagePageURL: URL) async throws -> CursorUsageSnapshot
    func fetchUsage(from usagePageURL: URL) async throws -> CursorUsageSnapshot
    func disconnect()
}

@MainActor
final class CursorSessionManager: CursorSessionManaging {
    private let dataStore: WKWebsiteDataStore
    private var connectionWindowController: UsageConnectionWindowController?
    private var activeScraper: CursorWebViewScraper?

    private(set) var isConnected = false

    init() {
        self.dataStore = WKWebsiteDataStore.default()
    }

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
    }

    func connect(to usagePageURL: URL) async throws -> CursorUsageSnapshot {
        let scraper = CursorWebViewScraper(mode: .interactive, usagePageURL: usagePageURL, dataStore: dataStore)
        let windowController = UsageConnectionWindowController(title: "Connect Cursor", webView: scraper.webView)

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
            if windowController.window?.isVisible == true {
                windowController.close()
            }
            throw error
        }
    }

    func fetchUsage(from usagePageURL: URL) async throws -> CursorUsageSnapshot {
        let scraper = CursorWebViewScraper(mode: .background, usagePageURL: usagePageURL, dataStore: dataStore)
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
            dataStore.removeData(ofTypes: types, for: records) {}
        }
    }
}
