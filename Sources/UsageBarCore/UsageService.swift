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

    private let store: SnapshotStore
    private var settings: AppSettings
    private var snapshot: UsageSnapshot
    private var lastAttempt: [Service: Date] = [:]
    private var isRefreshing = false

    public init(settings: AppSettings, store: SnapshotStore = SnapshotStore()) {
        self.store = store
        self.settings = settings
        self.snapshot = store.load() ?? UsageSnapshot()
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
    ///   "Refresh Now" menu item). The actor still refuses to run two refreshes
    ///   simultaneously.
    @discardableResult
    public func refresh(force: Bool = false) async -> UsageSnapshot {
        if isRefreshing { return snapshot }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let targets = Service.allCases.filter { service in
            guard isEnabled(service) else { return false }
            guard !force else { return true }
            guard let last = lastAttempt[service] else { return true }
            return now.timeIntervalSince(last) >= (Self.minimumInterval[service] ?? 60)
        }
        guard !targets.isEmpty else { return snapshot }

        let client = HTTPClient(proxy: settings.proxy)
        for service in targets { lastAttempt[service] = now }

        // Both providers are independent, so fire them together; total latency
        // is the slower of the two rather than the sum.
        let results = await withTaskGroup(of: (Service, ServiceResult).self,
                                          returning: [(Service, ServiceResult)].self) { group in
            for service in targets {
                group.addTask {
                    (service, await Self.fetch(service, using: client, now: now))
                }
            }
            var collected: [(Service, ServiceResult)] = []
            for await item in group { collected.append(item) }
            return collected
        }

        var merged = snapshot.results
        for (service, fresh) in results {
            var result = fresh
            // Keep the previous numbers when a refresh fails: showing "42%" with
            // a warning beats showing nothing at all.
            if result.usage == nil, let previous = merged[service]?.usage {
                result.usage = previous
            }
            merged[service] = result
        }

        snapshot = UsageSnapshot(results: merged, updatedAt: Date())
        store.save(snapshot)
        return snapshot
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
