import Foundation

extension Date {
    private static let sharedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Returns a human-readable relative time string
    /// - < 1 minute: "less than a minute"
    /// - < 1 hour: "X min"
    /// - < 1 day: "X hours"
    /// - >= 1 day: formatted date and time
    func relativeFormatted() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 0 {
            return "just now"
        }

        if interval < 60 {
            return "less than a minute"
        }

        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min"
        }

        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }

        return Self.sharedDateFormatter.string(from: self)
    }
}
