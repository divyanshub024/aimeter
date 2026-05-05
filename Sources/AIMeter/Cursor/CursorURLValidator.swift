import Foundation

enum CursorURLValidator {
    static let allowedHosts: Set<String> = [
        "cursor.com",
        "www.cursor.com"
    ]

    static func validatedUsageURL(from rawURL: String) throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), isAllowedCursorURL(url) else {
            throw CursorUsageError.invalidConfiguration("Cursor usage page URL must be an HTTPS cursor.com URL.")
        }

        return url
    }

    static func sanitizedUsageURL(_ rawURL: String) -> String {
        guard let url = try? validatedUsageURL(from: rawURL) else {
            return CursorSettings.default.usagePageURL
        }

        return url.absoluteString
    }

    static func isAllowedCursorURLString(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL) else {
            return false
        }

        return isAllowedCursorURL(url)
    }

    static func isAllowedCursorURL(_ url: URL) -> Bool {
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
