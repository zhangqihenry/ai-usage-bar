@testable import UsageBarCore
import Foundation

/// Refresh orchestration, settings compatibility, credential parsing and the
/// staleness rules. Network calls are replaced by an injected fetcher, so the
/// suite never leaves the machine.
enum ServiceTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    static func run() {
        suite("Refresh and pacing")
        keepsPreviousUsageOnFailure()
        rateLimitBackoffHoldsForcedRefresh()
        networkErrorsDoNotCountAgainstInterval()

        suite("Settings compatibility")
        partialSettingsKeepDefaults()
        badValuesCostOneField()

        suite("Credentials and parsing edge cases")
        claudeCredentialShapes()
        codexCredentialFile()
        classifierRewritesKind()
        codexWindowWithoutPercent()

        suite("Staleness")
        staleNumbersAreMuted()
        elapsedFormatting()

        suite("Threshold alerts and extra usage")
        thresholdAlerts()
        claudeExtraUsage()
    }

    // MARK: - Alerts

    private static func usageSnapshot(session: Double, at time: Date, error: String? = nil) -> UsageSnapshot {
        let usage = ServiceUsage(service: .codex,
                                 session: QuotaWindow(kind: .session, usedPercent: session),
                                 fetchedAt: time)
        return UsageSnapshot(results: [.codex: ServiceResult(usage: usage, errorCode: error)], updatedAt: time)
    }

    private static func thresholdAlerts() {
        let settings = codexOnly() // warn 70, danger 90
        var tracker = ThresholdTracker()

        check(tracker.alerts(for: usageSnapshot(session: 95, at: now), settings: settings, now: now).isEmpty,
              "first reading only records, even at 95%")
        check(tracker.alerts(for: usageSnapshot(session: 20, at: now), settings: settings, now: now).isEmpty,
              "falling back (window reset) is silent")

        let warn = tracker.alerts(for: usageSnapshot(session: 75, at: now), settings: settings, now: now)
        expectEqual(warn.map(\.level), [.warning], "crossing 70% warns")
        check(tracker.alerts(for: usageSnapshot(session: 80, at: now), settings: settings, now: now).isEmpty,
              "same band does not repeat")

        let failed = tracker.alerts(for: usageSnapshot(session: 99, at: now, error: "blocked"),
                                    settings: settings, now: now)
        check(failed.isEmpty, "a failed refresh with kept numbers never alerts")

        let danger = tracker.alerts(for: usageSnapshot(session: 92, at: now), settings: settings, now: now)
        expectEqual(danger.map(\.level), [.danger], "crossing 90% escalates")
        expectEqual(danger.first?.kind, .session, "alert names the window")
    }

    private static func claudeExtraUsage() {
        let on = Data(#"{"five_hour": {"utilization": 10}, "extra_usage": {"is_enabled": true, "utilization": 25.0, "monthly_limit": 5000}}"#.utf8)
        let usage = try? ClaudeProvider.parse(data: on, subscriptionType: nil, now: now)
        expectEqual(usage?.scoped.first { $0.scope == "Extra" }?.usedPercent, 25, "enabled extra usage is a row")

        let off = Data(#"{"five_hour": {"utilization": 10}, "extra_usage": {"is_enabled": false, "utilization": null}}"#.utf8)
        let hidden = try? ClaudeProvider.parse(data: off, subscriptionType: nil, now: now)
        check(hidden?.scoped.contains { $0.scope == "Extra" } == false, "disabled extra usage stays hidden")
    }

    // MARK: - Refresh

    /// Scripted fetcher: returns the queued results in order and counts calls.
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [Service: [ServiceResult]]
        private var counts: [Service: Int] = [:]

        init(_ queue: [Service: [ServiceResult]]) { self.queue = queue }

        func next(_ service: Service) -> ServiceResult {
            lock.lock(); defer { lock.unlock() }
            counts[service, default: 0] += 1
            guard var pending = queue[service], !pending.isEmpty else {
                return ServiceResult(errorCode: "unknown")
            }
            let result = pending.removeFirst()
            queue[service] = pending
            return result
        }

        func calls(_ service: Service) -> Int {
            lock.lock(); defer { lock.unlock() }
            return counts[service] ?? 0
        }
    }

    private static func codexOnly() -> AppSettings {
        var settings = AppSettings()
        settings.showClaude = false
        return settings
    }

    private static func service(_ script: Script, settings: AppSettings) -> UsageService {
        UsageService(settings: settings, persistent: false) { service, _, _ in script.next(service) }
    }

    private static func keepsPreviousUsageOnFailure() {
        let fetchedAt = now
        let usage = ServiceUsage(service: .codex,
                                 session: QuotaWindow(kind: .session, usedPercent: 42),
                                 fetchedAt: fetchedAt)
        let script = Script([.codex: [ServiceResult(usage: usage),
                                      ServiceResult(errorCode: "blocked")]])
        let usageService = service(script, settings: codexOnly())

        let first = blocking { await usageService.refresh(force: true) }
        let second = blocking { await usageService.refresh(force: true) }

        expectEqual(first.result(for: .codex)?.usage?.session?.usedPercent, 42, "first fetch")
        expectEqual(second.result(for: .codex)?.errorCode, "blocked", "failure is reported")
        expectEqual(second.result(for: .codex)?.usage?.session?.usedPercent, 42, "old numbers are kept")
        expectEqual(second.result(for: .codex)?.usage?.fetchedAt, fetchedAt,
                    "kept numbers keep their own fetch time")
    }

    private static func rateLimitBackoffHoldsForcedRefresh() {
        let script = Script([.codex: [ServiceResult(errorCode: UsageError.rateLimited.code)]])
        let usageService = service(script, settings: codexOnly())

        let first = blocking { await usageService.refresh(force: true) }
        _ = blocking { await usageService.refresh(force: true) }

        expectEqual(script.calls(.codex), 1, "a 429 pauses even forced refreshes")
        check(first.result(for: .codex)?.errorDetail?.hasPrefix("retry after") == true,
              "429 detail names the retry time")
    }

    private static func networkErrorsDoNotCountAgainstInterval() {
        let network = Script([.codex: [ServiceResult(errorCode: UsageError.network("").code),
                                       ServiceResult(errorCode: UsageError.network("").code)]])
        let offline = service(network, settings: codexOnly())
        _ = blocking { await offline.refresh(force: false) }
        _ = blocking { await offline.refresh(force: false) }
        expectEqual(network.calls(.codex), 2, "network failure is retried before the minimum interval")

        let http = Script([.codex: [ServiceResult(errorCode: "http_500"),
                                    ServiceResult(errorCode: "http_500")]])
        let failing = service(http, settings: codexOnly())
        _ = blocking { await failing.refresh(force: false) }
        _ = blocking { await failing.refresh(force: false) }
        expectEqual(http.calls(.codex), 1, "a server answer still respects the minimum interval")
    }

    // MARK: - Settings

    private static func partialSettingsKeepDefaults() {
        let json = Data(#"{"refreshIntervalSeconds": 600, "proxy": {"mode": "manual"}}"#.utf8)
        let decoded = try? JSONDecoder().decode(AppSettings.self, from: json)
        expectEqual(decoded?.refreshIntervalSeconds, 600, "known key is read")
        expectEqual(decoded?.fontSize, AppSettings().fontSize, "missing key gets its default")
        expectEqual(decoded?.proxy.mode, .manual, "nested known key is read")
        expectEqual(decoded?.proxy.port, ProxyConfiguration().port, "nested missing key gets its default")
    }

    private static func badValuesCostOneField() {
        let json = Data(#"{"showCodex": "yes", "warnThreshold": 60, "proxy": {"port": "abc"}}"#.utf8)
        let decoded = try? JSONDecoder().decode(AppSettings.self, from: json)
        expectNotNil(decoded, "a bad value does not reject the file")
        expectEqual(decoded?.showCodex, true, "bad bool falls back")
        expectEqual(decoded?.warnThreshold, 60, "neighbouring value survives")
        expectEqual(decoded?.proxy.port, 7897, "bad port falls back")
    }

    // MARK: - Credentials and parsing

    private static func claudeCredentialShapes() {
        let wrapped = Data(#"{"claudeAiOauth": {"accessToken": "tok", "refreshToken": "ref", "expiresAt": 1790000000000, "subscriptionType": "max"}}"#.utf8)
        let parsed = ClaudeCredentialStore.parse(data: wrapped, source: "file")
        expectEqual(parsed?.accessToken, "tok", "wrapped token")
        expectEqual(parsed?.subscriptionType, "max", "subscription type")
        expectEqual(parsed?.expiresAt, Date(timeIntervalSince1970: 1_790_000_000), "expiresAt is milliseconds")

        let flat = Data(#"{"accessToken": "flat"}"#.utf8)
        expectEqual(ClaudeCredentialStore.parse(data: flat, source: "file")?.accessToken, "flat", "flat shape")
        check(ClaudeCredentialStore.parse(data: Data(#"{"claudeAiOauth": {}}"#.utf8), source: "file") == nil,
              "no token is no credentials")
    }

    private static func codexCredentialFile() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("usagebar-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let previous = ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_HOME", directory.path, 1)
        defer {
            if let previous { setenv("CODEX_HOME", previous, 1) } else { unsetenv("CODEX_HOME") }
        }
        let file = directory.appendingPathComponent("auth.json")

        try? Data(#"{"OPENAI_API_KEY": "sk-test"}"#.utf8).write(to: file)
        expectError({ _ = try CodexCredentialStore.load() }, code: "credentials_missing")

        try? Data(#"{"tokens": {"access_token": "abc", "account_id": "acct-1"}}"#.utf8).write(to: file)
        let credentials = try? CodexCredentialStore.load()
        expectEqual(credentials?.accessToken, "abc", "codex token")
        expectEqual(credentials?.accountID, "acct-1", "codex account id")
    }

    private static func classifierRewritesKind() {
        let a = QuotaWindow(kind: .weekly, usedPercent: 10)
        let b = QuotaWindow(kind: .weekly, usedPercent: 20)
        let buckets = WindowClassifier.buckets(primary: (604_800, a), secondary: (604_800, b))
        expectEqual(buckets.weekly?.usedPercent, 10, "first weekly window wins the weekly slot")
        expectEqual(buckets.session?.usedPercent, 20, "overflow lands in the free slot")
        expectEqual(buckets.session?.kind, .session, "kind follows the slot")
    }

    private static func codexWindowWithoutPercent() {
        let none = Data(#"{"rate_limit": {"primary_window": {"limit_window_seconds": 18000}}}"#.utf8)
        expectError({ _ = try CodexProvider.parse(data: none, emailFallback: nil, now: now) },
                    code: "decoding")

        let partial = Data(#"{"rate_limit": {"primary_window": {"used_percent": 30, "limit_window_seconds": 18000}, "secondary_window": {"limit_window_seconds": 604800}}}"#.utf8)
        let usage = try? CodexProvider.parse(data: partial, emailFallback: nil, now: now)
        expectEqual(usage?.session?.usedPercent, 30, "window with a percent is kept")
        check(usage?.weekly == nil, "window without a percent is dropped, not shown as 0%")
    }

    // MARK: - Staleness

    private static func staleNumbersAreMuted() {
        var settings = codexOnly()
        settings.refreshIntervalSeconds = 300
        let usage = ServiceUsage(service: .codex,
                                 session: QuotaWindow(kind: .session, usedPercent: 95),
                                 weekly: QuotaWindow(kind: .weekly, usedPercent: 10),
                                 fetchedAt: now)
        let snapshot = UsageSnapshot(results: [.codex: ServiceResult(usage: usage)], updatedAt: now)

        let fresh = MenuBarTitle.segments(snapshot: snapshot, settings: settings, now: now.addingTimeInterval(60))
        let old = MenuBarTitle.segments(snapshot: snapshot, settings: settings, now: now.addingTimeInterval(86_400))
        expectEqual(fresh.first { $0.text.contains("95") }?.severity, .danger, "fresh 95% is red")
        expectEqual(old.first { $0.text.contains("95") }?.severity, .muted, "day old 95% is muted")
        check(usage.isStale(limit: settings.staleAfter, now: now.addingTimeInterval(86_400)), "day old is stale")
        check(!usage.isStale(limit: settings.staleAfter, now: now.addingTimeInterval(600)), "10 min old is fresh")
    }

    private static func elapsedFormatting() {
        expectEqual(Format.elapsed(since: now.addingTimeInterval(-30), now: now), "<1m", "seconds")
        expectEqual(Format.elapsed(since: now.addingTimeInterval(-7_200), now: now), "2h", "hours")
        expectEqual(Format.elapsed(since: now.addingTimeInterval(-90_000), now: now), "1d1h", "days")
    }
}

/// Runs async work from the synchronous suites. Detached, because the test
/// entry point blocks the main thread while it waits.
private func blocking<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.value = await body()
        done.signal()
    }
    done.wait()
    return box.value!
}

/// Carries the result out of the detached task; the semaphore orders access.
private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
