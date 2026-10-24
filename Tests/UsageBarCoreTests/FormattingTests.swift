@testable import UsageBarCore
import Foundation

/// Tests for the pure formatting helpers and the menu bar title layout. These
/// are the pieces users see, so a regression here is visible immediately.
enum FormattingTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    static func run() {
        suite("Formatting")
        countdowns()
        bars()
        percentages()
        menuBarTitle()
        severity()
        settings()
        snapshotCoding()
    }

    // MARK: - Countdown

    private static func countdowns() {
        expectEqual(Format.countdown(to: now.addingTimeInterval(-5), now: now), "now", "past")
        expectEqual(Format.countdown(to: now.addingTimeInterval(30), now: now), "<1m", "seconds")
        expectEqual(Format.countdown(to: now.addingTimeInterval(45 * 60), now: now), "45m", "minutes")
        expectEqual(Format.countdown(to: now.addingTimeInterval(2 * 3_600 + 13 * 60), now: now),
                    "2h13m", "hours")
        expectEqual(Format.countdown(to: now.addingTimeInterval(3 * 3_600), now: now), "3h", "whole hours")
        expectEqual(Format.countdown(to: now.addingTimeInterval(3 * 86_400 + 4 * 3_600), now: now),
                    "3d4h", "days")
        expectEqual(Format.countdown(to: nil, now: now), "–", "missing date")
    }

    // MARK: - Bars and percentages

    private static func bars() {
        expectEqual(Format.bar(0).count, 10, "bar width")
        expectEqual(Format.bar(50), "█████░░░░░", "half bar")
        expectEqual(Format.bar(100), "██████████", "full bar")
        expectEqual(Format.bar(150), "██████████", "above 100 is clamped")
    }

    private static func percentages() {
        expectEqual(Format.percent(0), "0%", "zero")
        expectEqual(Format.percent(12.4), "12%", "round down")
        expectEqual(Format.percent(12.6), "13%", "round up")
        expectEqual(Format.percent(100), "100%", "hundred")
    }

    // MARK: - Menu bar title

    private static func snapshot(session: Double?,
                                 weekly: Double?,
                                 error: String? = nil) -> UsageSnapshot {
        let codex = ServiceUsage(
            service: .codex,
            plan: "plus",
            session: session.map { QuotaWindow(kind: .session, usedPercent: $0) },
            weekly: weekly.map { QuotaWindow(kind: .weekly, usedPercent: $0) }
        )
        return UsageSnapshot(results: [.codex: ServiceResult(usage: codex, errorCode: error)],
                             updatedAt: now)
    }

    private static func menuBarTitle() {
        var settings = AppSettings()
        settings.showClaude = false

        expectEqual(MenuBarTitle.plainText(snapshot: snapshot(session: 12, weekly: 48),
                                           settings: settings),
                    "Cx 12/48", "both windows")

        expectEqual(MenuBarTitle.plainText(snapshot: snapshot(session: nil, weekly: 0),
                                           settings: settings),
                    "Cx –/0", "missing 5h window")

        settings.displayMode = .weekly
        expectEqual(MenuBarTitle.plainText(snapshot: snapshot(session: 12, weekly: 48),
                                           settings: settings),
                    "Cx 48", "weekly only")

        settings.displayMode = .both
        settings.showRemaining = true
        expectEqual(MenuBarTitle.plainText(snapshot: snapshot(session: 12, weekly: 48),
                                           settings: settings),
                    "Cx 88/52", "remaining mode")

        settings.showRemaining = false
        expectEqual(MenuBarTitle.plainText(snapshot: snapshot(session: 12, weekly: 48, error: "blocked"),
                                           settings: settings),
                    "Cx 12/48!", "error marker")
    }

    private static func severity() {
        var settings = AppSettings()
        settings.warnThreshold = 70
        settings.dangerThreshold = 90

        expectEqual(MenuBarTitle.severity(for: 10, settings: settings), .normal, "normal")
        expectEqual(MenuBarTitle.severity(for: 70, settings: settings), .warning, "warning at threshold")
        expectEqual(MenuBarTitle.severity(for: 95, settings: settings), .danger, "danger")
    }

    // MARK: - Settings

    private static func settings() {
        var settings = AppSettings()
        settings.refreshIntervalSeconds = 5
        settings.warnThreshold = 90
        settings.dangerThreshold = 50
        settings.fontSize = 100

        let normalized = settings.normalized()
        expectEqual(normalized.refreshIntervalSeconds, 60, "interval floor")
        check(normalized.dangerThreshold > normalized.warnThreshold, "thresholds stay ordered")
        expectEqual(normalized.fontSize, 16, "font ceiling")

        var proxy = ProxyConfiguration()
        check(proxy.connectionProxyDictionary == nil, "system mode defers to macOS")

        proxy.mode = .manual
        proxy.port = 7897
        expectEqual(proxy.connectionProxyDictionary?["HTTPSProxy"] as? String,
                    "127.0.0.1", "manual proxy host")
        expectEqual(proxy.connectionProxyDictionary?["HTTPSPort"] as? Int, 7897, "manual proxy port")

        proxy.mode = .direct
        expectEqual(proxy.connectionProxyDictionary?["HTTPSEnable"] as? Int, 0, "direct disables proxy")
    }

    /// The on-disk snapshot must be keyed by service name, not by Foundation's
    /// alternating key/value array for non-string dictionary keys.
    private static func snapshotCoding() {
        let usage = ServiceUsage(service: .codex,
                                 plan: "plus",
                                 session: QuotaWindow(kind: .session, usedPercent: 12))
        let snapshot = UsageSnapshot(results: [.codex: ServiceResult(usage: usage)], updatedAt: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            check(false, "snapshot failed to encode")
            return
        }

        let text = String(decoding: data, as: UTF8.self)
        check(text.contains("\"codex\""), "snapshot is keyed by service name")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(UsageSnapshot.self, from: data)
        expectEqual(decoded?.results[.codex]?.usage?.session?.usedPercent, 12, "snapshot round trip")
        expectEqual(decoded?.updatedAt, now, "timestamp round trip")
    }
}
