import Foundation

extension Date {
    /// Returns a human-readable relative time string
    /// - < 1 minute: "less than a minute"
    /// - < 1 hour: "X min"
    /// - < 1 day: "X hours"
    /// - >= 1 day: formatted date and time
    func relativeFormatted() -> String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        // Future dates
        if interval < 0 {
            return "just now"
        }

        // Less than 1 minute
        if interval < 60 {
            return "less than a minute"
        }

        // Less than 1 hour - show minutes only
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min"
        }

        // Less than 1 day - show hours only
        if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }

        // More than 1 day - show formatted date and time
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
