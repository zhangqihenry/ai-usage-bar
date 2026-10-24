import Foundation

/// String formatting shared by the menu bar title, the menu rows and the CLI.
///
/// Keeping this in Core (and pure) makes the visual output easy to unit test
/// without launching an app.
public enum Format {
    /// "42%" – rounded to whole percent, the precision the providers report.
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Compact countdown used next to each window: "3d4h", "2h13m", "45m", "now".
    ///
    /// Deliberately coarse: a menu row is 30 characters wide, and nobody needs
    /// seconds in a quota reset estimate.
    public static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "–" }
        let seconds = Int(date.timeIntervalSince(now).rounded())
        if seconds <= 0 { return "now" }
        if seconds < 60 { return "<1m" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }

        let hours = minutes / 60
        if hours < 24 {
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h\(remainder)m"
        }

        let days = hours / 24
        let remainder = hours % 24
        return remainder == 0 ? "\(days)d" : "\(days)d\(remainder)h"
    }

    /// Coarse age of a past moment in the same units as `countdown`: "45m",
    /// "3h", "131d5h". Used for "showing data from 2h ago".
    public static func elapsed(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "<1m" }
        return countdown(to: now.addingTimeInterval(seconds), now: now)
    }

    // Built once: DateFormatter is expensive to create and these run on every
    // render. Formatting from several threads is safe on macOS.
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HH:mm"
        return formatter
    }()

    /// "14:32" – local wall clock time, used for "updated at".
    public static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// "Oct 23 14:32" – for the CLI and diagnostics.
    public static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }

    /// A 10 cell ASCII progress bar, e.g. `████░░░░░░`.
    ///
    /// ASCII blocks are used instead of a drawn view here because the CLI needs
    /// the same output; the AppKit menu draws a real bar.
    public static func bar(_ usedPercent: Double, width: Int = 10) -> String {
        let clamped = max(0, min(100, usedPercent))
        let filled = Int((clamped / 100 * Double(width)).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    /// Value shown for one bucket in the menu bar title. Missing windows become
    /// an en dash so the two services stay visually aligned.
    public static func titleValue(_ window: QuotaWindow?,
                                  remaining: Bool,
                                  style: TitleStyle) -> String {
        guard let window else { return "–" }
        let value = remaining ? window.remainingPercent : window.usedPercent
        switch style {
        case .compact:
            return "\(Int(value.rounded()))"
        case .labeled:
            return percent(value)
        }
    }
}
