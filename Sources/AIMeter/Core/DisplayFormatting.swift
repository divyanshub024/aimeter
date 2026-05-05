import Foundation

enum DisplayFormatting {
    static func percent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 100)

        if abs(clamped.rounded() - clamped) < 0.05 {
            return "\(Int(clamped.rounded()))%"
        }

        return String(format: "%.1f%%", clamped)
    }

    static func relativeTimestamp(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
