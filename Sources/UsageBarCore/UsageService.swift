import Foundation

/// Orchestrates the providers: decides what to refresh (and how often), runs the
/// calls in parallel, merges results into the last known snapshot and persists
/// it.
///
/// An `actor` because the UI may ask for a refresh while a timer driven refresh
/// is already running; the actor guarantees only one runs at a time and that the
/// merged snapshot is never written from two tasks at once.
public actor UsageService {
    /// Minimum gap between two calls per service, regardless of the user's
    /// polling interval. Claude's endpoint rate limits aggressively (a handful of
    /// calls per token window), so it gets a much larger floor than Codex.
    static let minimumInterval: [Service: TimeInterval] = [
        .codex: 60,
        .claude: 240
    ]

    /// Pause after an HTTP 429, doubled for every consecutive 429 and capped.
    /// Honoured even by forced refreshes: retrying into a rate limit only
    /// extends it.
    static let rateLimitBackoff: TimeInterval = 300
    static let rateLimitBackoffCap: TimeInterval = 3600

    /// Performs one provider call. Injectable so tests can drive the merge and
    /// backoff logic without the network.
    public typealias Fetcher = @Sendable (Service, HTTPClient, Date) async -> ServiceResult

    private let store: SnapshotStore
    private let persistent: Bool
    private let fetcher: Fetcher
    private var settings: AppSettings
    private var snapshot: UsageSnapshot
    private var lastAttempt: [Service: Date] = [:]
    private var rateLimitStreak: [Service: Int] = [:]
    private var notBefore: [Service: Date] = [:]
    private var client: HTTPClient?
    private var isRefreshing = false

    /// - Parameter persistent: false keeps everything in memory: no cached
    ///   snapshot is loaded and nothing is written. The CLI uses this so a one
    ///   shot `--print` reports only what it fetched itself and never rewrites
    ///   the running app's cache.
    /// - Parameter fetcher: replaces the real provider calls (tests only).
    public init(settings: AppSettings,
                store: SnapshotStore = SnapshotStore(),
                persistent: Bool = true,
                fetcher: Fetcher? = nil) {
        self.store = store
        self.persistent = persistent
        self.fetcher = fetcher ?? { service, client, now in
            await UsageService.fetch(service, using: client, now: now)
        }
        self.settings = settings
        self.snapshot = persistent ? (store.load() ?? UsageSnapshot()) : UsageSnapshot()
    }

    public func apply(_ settings: AppSettings) {
        self.settings = settings
    }

    /// Last known state, including cached data from a previous launch.
    public func cachedSnapshot() -> UsageSnapshot { snapshot }

    public func isEnabled(_ service: Service) -> Bool {
        service == .codex ? settings.showCodex : settings.showClaude
    }

    /// Refreshes the enabled services.
    ///
    /// - Parameter force: ignore the per-service minimum interval (used by the
    ///   "Refresh Now" menu item). A 429 backoff still applies, and the actor
    ///   still refuses to run two refreshes simultaneously.
    @discardableResult
    public func refresh(force: Bool = false) async -> UsageSnapshot {
        if isRefreshing { return snapshot }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let targets = Service.allCases.filter { service in
            guard isEnabled(service) else { return false }
            if let until = notBefore[service], until > now { return false }
            guard !force else { return true }
            guard let last = lastAttempt[service] else { return true }
            return now.timeIntervalSince(last) >= (Self.minimumInterval[service] ?? 60)
        }
        guard !targets.isEmpty else { return snapshot }

        let client = currentClient()
        for service in targets { lastAttempt[service] = now }

        // Both providers are independent, so fire them together; total latency
        // is the slower of the two rather than the sum.
        let fetcher = self.fetcher
        let results = await withTaskGroup(of: (Service, ServiceResult).self,
                                          returning: [(Service, ServiceResult)].self) { group in
            for service in targets {
                group.addTask {
                    (service, await fetcher(service, client, now))
                }
            }
            var collected: [(Service, ServiceResult)] = []
            for await item in group { collected.append(item) }
            return collected
        }

        var merged = snapshot.results
        for (service, fresh) in results {
            var result = fresh
            schedule(after: &result, for: service, now: Date())
            // Keep the previous numbers when a refresh fails: showing "42%" with
            // a warning beats showing nothing at all. The kept usage carries its
            // own `fetchedAt`, which the UI uses to flag it as stale.
            if result.usage == nil, let previous = merged[service]?.usage {
                result.usage = previous
            }
            merged[service] = result
        }

        // `updatedAt` is the time of the last attempt, successful or not.
        // Freshness of the numbers themselves is `ServiceUsage.fetchedAt`.
        snapshot = UsageSnapshot(results: merged, updatedAt: Date())
        if persistent { store.save(snapshot) }
        return snapshot
    }

    /// Updates the per-service pacing after a call finished.
    private func schedule(after result: inout ServiceResult, for service: Service, now: Date) {
        switch result.errorCode {
        case UsageError.rateLimited.code:
            let streak = (rateLimitStreak[service] ?? 0) + 1
            rateLimitStreak[service] = streak
            let delay = min(Self.rateLimitBackoffCap,
                            Self.rateLimitBackoff * pow(2, Double(streak - 1)))
            let until = now.addingTimeInterval(delay)
            notBefore[service] = until
            result.errorDetail = "retry after \(Format.clock(until))"
        case UsageError.network("").code:
            // The request never reached the vendor, so it cost no quota: let the
            // next tick retry instead of waiting out the minimum interval.
            lastAttempt[service] = nil
            rateLimitStreak[service] = nil
            notBefore[service] = nil
        default:
            rateLimitStreak[service] = nil
            notBefore[service] = nil
        }
    }

    /// One client per proxy configuration, so connections are reused between
    /// refreshes and a proxy change takes effect on the next call.
    private func currentClient() -> HTTPClient {
        if let client, client.proxy == settings.proxy { return client }
        client?.invalidate()
        let fresh = HTTPClient(proxy: settings.proxy)
        client = fresh
        return fresh
    }

    /// Runs one provider, converting throws into a storable `ServiceResult`.
    static func fetch(_ service: Service,
                      using client: HTTPClient,
                      now: Date) async -> ServiceResult {
        do {
            let usage: ServiceUsage
            switch service {
            case .codex:
                usage = try await CodexProvider().fetch(using: client, now: now)
            case .claude:
                usage = try await ClaudeProvider().fetch(using: client, now: now)
            }
            return ServiceResult(usage: usage)
        } catch let error as UsageError {
            return ServiceResult(usage: nil,
                                 errorCode: error.code,
                                 errorDetail: detail(of: error))
        } catch {
            return ServiceResult(usage: nil,
                                 errorCode: "unknown",
                                 errorDetail: error.localizedDescription)
        }
    }

    /// The technical half of an error, shown in parentheses in the UI.
    static func detail(of error: UsageError) -> String? {
        switch error {
        case .credentialsMissing(let hint): return hint
        case .credentialsExpired(let date):
            guard let date else { return nil }
            return "expired \(Format.timestamp(date))"
        case .network(let message): return message
        case .decoding(let message): return message
        case .http(let status): return "HTTP \(status)"
        case .unauthorized, .blocked, .rateLimited: return nil
        }
    }
}
