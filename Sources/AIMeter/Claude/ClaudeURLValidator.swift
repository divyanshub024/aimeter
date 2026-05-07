import Foundation

enum ClaudeURLValidator {
    static let allowedHosts: Set<String> = [
        "claude.ai",
        "www.claude.ai"
    ]

    static func validatedUsageURL(from rawURL: String) throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), isAllowedClaudeURL(url) else {
            throw ProviderUsageError.invalidConfiguration("Claude usage page URL must be an HTTPS claude.ai URL.")
        }

        return url
    }

    static func sanitizedUsageURL(_ rawURL: String) -> String {
        guard let url = try? validatedUsageURL(from: rawURL) else {
            return ClaudeSettings.default.usagePageURL
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            return ClaudeSettings.default.usagePageURL
        }

        return url.absoluteString
    }

    static func isAllowedClaudeURLString(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL) else {
            return false
        }

        return isAllowedClaudeURL(url)
    }

    static func isUsageSettingsURLString(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL), isAllowedClaudeURL(url) else {
            return false
        }

        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() == "settings/usage"
    }

    static func isAllowedClaudeURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else {
            return false
        }

        guard url.user == nil, url.password == nil else {
            return false
        }

        guard url.port == nil else {
            return false
        }

        guard let host = url.host?.lowercased() else {
            return false
        }

        return allowedHosts.contains(host)
    }
}
