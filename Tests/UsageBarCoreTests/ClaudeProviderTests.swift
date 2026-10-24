@testable import UsageBarCore
import Foundation

/// Parser tests for the Anthropic OAuth usage endpoint. Two response shapes have
/// shipped: flat buckets, and a structured `limits` array. Both are covered.
enum ClaudeProviderTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func run() {
        suite("Claude parsing")
        flatBuckets()
        structuredLimits()
        emptyResponse()
        timestampFormats()
    }

    private static func flatBuckets() {
        let usage = try? ClaudeProvider.parse(data: fixtureData("claude_flat"),
                                              subscriptionType: "max",
                                              now: now)
        guard let usage else {
            check(false, "flat fixture failed to parse")
            return
        }

        expectEqual(usage.service, .claude, "service")
        expectEqual(usage.plan, "max", "subscription type")
        expectEqual(usage.session?.usedPercent, 63, "5h percent")
        expectEqual(usage.weekly?.usedPercent, 13, "week percent")
        expectNotNil(usage.session?.resetsAt, "5h reset")
        expectNotNil(usage.weekly?.resetsAt, "week reset")

        // `utilization: 1.0` means one percent, not one hundred percent.
        let sonnet = usage.scoped.first { $0.scope == "Sonnet" }
        expectEqual(sonnet?.usedPercent, 1, "Sonnet weekly percent")
    }

    private static func structuredLimits() {
        let usage = try? ClaudeProvider.parse(data: fixtureData("claude_limits"),
                                              subscriptionType: nil,
                                              now: now)
        guard let usage else {
            check(false, "limits fixture failed to parse")
            return
        }

        expectEqual(usage.session?.usedPercent, 42, "session from limits")
        expectEqual(usage.weekly?.usedPercent, 18, "weekly_all from limits")
        expectEqual(usage.scoped.first?.scope, "Opus", "scoped model name")
        expectEqual(usage.scoped.first?.usedPercent, 7, "scoped percent")

        expectEqual(ClaudeProvider.classify(kind: "session"), .session, "kind session")
        expectEqual(ClaudeProvider.classify(kind: "weekly_all"), .weekly, "kind weekly_all")
        expectEqual(ClaudeProvider.classify(kind: nil), .weekly, "nil kind defaults to weekly")
    }

    private static func emptyResponse() {
        let json = Data(#"{"five_hour": null, "seven_day": null}"#.utf8)
        expectError({
            _ = try ClaudeProvider.parse(data: json, subscriptionType: nil, now: now)
        }, code: "decoding")
    }

    private static func timestampFormats() {
        expectNotNil(ISO8601.parse("2026-10-27T00:59:59.951713+00:00"), "microseconds + offset")
        expectNotNil(ISO8601.parse("2026-10-27T00:59:59Z"), "plain Zulu")
        check(ISO8601.parse("") == nil, "empty string is nil")
    }
}
