@testable import UsageBarCore
import Foundation

/// Parser tests for the Codex endpoint. Fixtures under `Fixtures/` mirror the
/// live API shape, with identifiers anonymised.
enum CodexProviderTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func run() {
        suite("Codex parsing")
        singleWeeklyWindow()
        twoWindows()
        unknownWindowLength()
        malformedPayload()
    }

    /// Pro Lite accounts answer with a single 7 day window in the primary slot.
    /// That must land in `weekly`, not `session`.
    private static func singleWeeklyWindow() {
        let usage = try? CodexProvider.parse(data: fixtureData("codex_single_window"),
                                             emailFallback: nil,
                                             now: now)
        guard let usage else {
            check(false, "single window fixture failed to parse")
            return
        }

        expectEqual(usage.service, .codex, "service")
        expectEqual(usage.plan, "prolite", "plan")
        expectEqual(usage.account, "test@example.com", "account from payload")
        check(usage.session == nil, "5h window should be absent on this plan")
        expectEqual(usage.weekly?.usedPercent, 0, "weekly percent")
        expectEqual(usage.weekly?.kind, .weekly, "weekly kind")
        expectEqual(usage.weekly?.resetsAt,
                    Date(timeIntervalSince1970: 1_793_325_915),
                    "reset time")
    }

    private static func twoWindows() {
        let usage = try? CodexProvider.parse(data: fixtureData("codex_two_windows"),
                                             emailFallback: "fallback@example.com",
                                             now: now)
        guard let usage else {
            check(false, "two window fixture failed to parse")
            return
        }

        expectEqual(usage.session?.usedPercent, 37.5, "session percent")
        expectEqual(usage.session?.kind, .session, "session kind")
        expectEqual(usage.weekly?.usedPercent, 100, "112% is clamped to 100")
        check(usage.notes.contains("limit reached"), "limit_reached becomes a note")
        check(usage.notes.contains("credits 3"), "credits balance becomes a note")
        // The explicit reset_at wins over reset_after_seconds.
        expectEqual(usage.session?.resetsAt,
                    Date(timeIntervalSince1970: 1_793_328_000),
                    "reset precedence")
    }

    /// Unknown window lengths fall back to API ordering: primary = session.
    private static func unknownWindowLength() {
        let session = QuotaWindow(kind: .session, usedPercent: 10)
        let weekly = QuotaWindow(kind: .weekly, usedPercent: 20)
        let buckets = WindowClassifier.buckets(primary: (nil, session), secondary: (nil, weekly))
        expectEqual(buckets.session?.usedPercent, 10, "session fallback")
        expectEqual(buckets.weekly?.usedPercent, 20, "weekly fallback")

        expectEqual(WindowClassifier.kind(forSeconds: 18_000), .session, "18000s")
        expectEqual(WindowClassifier.kind(forSeconds: 17_999), .session, "17999s")
        expectEqual(WindowClassifier.kind(forSeconds: 604_800), .weekly, "604800s")
        expectEqual(WindowClassifier.kind(forSeconds: 604_799), .weekly, "604799s")
        check(WindowClassifier.kind(forSeconds: 3_600) == nil, "1h is not a known bucket")
        check(WindowClassifier.kind(forSeconds: nil) == nil, "nil length is unknown")
    }

    private static func malformedPayload() {
        expectError({
            _ = try CodexProvider.parse(data: Data("{}".utf8), emailFallback: nil, now: now)
        }, code: "decoding")
    }
}
