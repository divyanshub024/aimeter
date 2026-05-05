import Foundation
import WebKit

@MainActor
final class CursorWebViewScraper: NSObject {
    enum Mode {
        case interactive
        case background
    }

    let webView: WKWebView

    private let mode: Mode
    private let usagePageURL: URL
    private let timeoutSeconds: TimeInterval
    private let contentController: WKUserContentController

    private var continuation: CheckedContinuation<CursorUsageSnapshot, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var hasResolved = false

    init(mode: Mode, usagePageURL: URL, dataStore: WKWebsiteDataStore) {
        self.mode = mode
        self.usagePageURL = usagePageURL
        self.timeoutSeconds = mode == .interactive ? 180 : 25

        let contentController = WKUserContentController()
        self.contentController = contentController

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        contentController.addUserScript(
            WKUserScript(
                source: Self.networkInterceptorScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        contentController.add(self, name: Self.messageHandlerName)
        webView.navigationDelegate = self
    }

    func start() async throws -> CursorUsageSnapshot {
        if continuation != nil {
            throw CursorUsageError.syncFailed("Cursor load is already running.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = URLRequest(url: usagePageURL)
            webView.load(request)
            scheduleTimeout()
        }
    }

    func cancel() {
        resolve(.failure(CursorUsageError.cancelled))
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            await MainActor.run {
                let message: String
                switch self.mode {
                case .interactive:
                    message = "Cursor usage card did not load. Finish sign-in and try again."
                case .background:
                    message = "Cursor usage card was not found on the dashboard."
                }
                self.resolve(.failure(CursorUsageError.syncFailed(message)))
            }
        }
    }

    private func startPollingDOM() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollDOM()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    private func stopPollingDOM() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollDOM() async {
        guard !hasResolved else {
            return
        }

        let script = """
        ({
          text: document.body ? document.body.innerText : "",
          url: window.location.href
        })
        """

        do {
            guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
                return
            }

            let text = result["text"] as? String ?? ""
            let url = result["url"] as? String ?? webView.url?.absoluteString ?? usagePageURL.absoluteString

            switch CursorDashboardParser.parseDOMText(text, sourceURL: url) {
            case .usage(let snapshot):
                resolve(.success(snapshot))
            case .authRequired where mode == .background:
                resolve(.failure(CursorUsageError.authExpired))
            case .authRequired, .noMatch:
                break
            }
        } catch {
            if mode == .background {
                resolve(.failure(CursorUsageError.syncFailed("Failed reading the Cursor dashboard.")))
            }
        }
    }

    private func handleNetworkMessage(_ payload: [String: Any]) {
        guard !hasResolved else {
            return
        }

        let body = payload["body"] as? String ?? ""
        let sourceURL = payload["url"] as? String ?? webView.url?.absoluteString ?? usagePageURL.absoluteString
        guard CursorURLValidator.isAllowedCursorURLString(sourceURL) else {
            return
        }

        switch CursorDashboardParser.parseResponseBody(body, sourceURL: sourceURL) {
        case .usage(let snapshot):
            resolve(.success(snapshot))
        case .authRequired where mode == .background:
            resolve(.failure(CursorUsageError.authExpired))
        case .authRequired, .noMatch:
            break
        }
    }

    private func resolve(_ result: Result<CursorUsageSnapshot, Error>) {
        guard !hasResolved else {
            return
        }

        hasResolved = true
        stopPollingDOM()
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        contentController.removeScriptMessageHandler(forName: Self.messageHandlerName)

        switch result {
        case .success(let snapshot):
            continuation?.resume(returning: snapshot)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }

        continuation = nil
    }

    private static let messageHandlerName = "cursorNetworkBridge"

    nonisolated static func isBenignNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        // WebKit reports some normal auth hand-offs as a frame load interruption.
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return true
        }

        return false
    }

    private static let networkInterceptorScript = """
    (() => {
      if (window.__aimeterCursorHookInstalled) {
        return;
      }
      window.__aimeterCursorHookInstalled = true;

      const maxLength = 50000;
      const allowedHosts = new Set(["cursor.com", "www.cursor.com"]);

      const allowedURL = (value) => {
        try {
          const url = new URL(value, window.location.href);
          return url.protocol === "https:" && allowedHosts.has(url.hostname.toLowerCase());
        } catch (_) {
          return false;
        }
      };

      const post = (payload) => {
        try {
          if (!allowedURL(payload.url || "")) {
            return;
          }
          window.webkit.messageHandlers.cursorNetworkBridge.postMessage(payload);
        } catch (_) {}
      };

      const clip = (value) => {
        if (typeof value !== "string") {
          return "";
        }
        return value.length > maxLength ? value.slice(0, maxLength) : value;
      };

      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        const response = await originalFetch.apply(this, args);
        try {
          const input = args[0];
          const requestURL = typeof input === "string" ? input : (input && input.url) || "";
          const url = response.url || requestURL;
          if (!allowedURL(url)) {
            return response;
          }
          const cloned = response.clone();
          const body = await cloned.text();
          post({ url, body: clip(body) });
        } catch (_) {}
        return response;
      };

      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;

      XMLHttpRequest.prototype.open = function(method, url) {
        this.__aimeterURL = url;
        return originalOpen.apply(this, arguments);
      };

      XMLHttpRequest.prototype.send = function() {
        this.addEventListener("load", function() {
          try {
            const url = this.responseURL || this.__aimeterURL || "";
            if (!allowedURL(url)) {
              return;
            }
            const body = typeof this.responseText === "string" ? this.responseText : "";
            post({ url, body: clip(body) });
          } catch (_) {}
        });
        return originalSend.apply(this, arguments);
      };
    })();
    """
}

@MainActor
extension CursorWebViewScraper: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startPollingDOM()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !Self.isBenignNavigationError(error) else {
            return
        }

        guard mode == .background else {
            return
        }

        resolve(.failure(CursorUsageError.syncFailed(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !Self.isBenignNavigationError(error) else {
            return
        }

        guard mode == .background else {
            return
        }

        resolve(.failure(CursorUsageError.syncFailed(error.localizedDescription)))
    }
}

@MainActor
extension CursorWebViewScraper: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else {
            return
        }

        guard let payload = message.body as? [String: Any] else {
            return
        }

        handleNetworkMessage(payload)
    }
}
