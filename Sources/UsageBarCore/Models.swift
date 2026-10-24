import Foundation

// MARK: - Service

/// One of the AI subscription products whose rolling quota this app shows.
///
/// The raw values are used as JSON keys in the on-disk snapshot, so they must
/// stay stable across releases.
public enum Service: String, Codable, CaseIterable, Sendable {
    /// OpenAI ChatGPT / Codex usage (5 h window + weekly window).
    case codex
    /// Anthropic Claude usage (5 h window + weekly window).
    case claude

    /// Two letter prefix drawn in the menu bar, e.g. "Cx 12/48".
    public var shortLabel: String {
        switch self {
        case .codex: return "Cx"
        case .claude: return "Cl"
        }
    }

    /// Name shown in menus and diagnostics.
    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }

    /// SF Symbol used as the menu item icon.
    public var symbolName: String {
        switch self {
        case .codex: return "cube.transparent"
        case .claude: return "sparkles"
        }
    }
}

// MARK: - Quota windows

/// The two kinds of rolling quota both providers expose.
///
/// The providers report absolute timestamps only; the window length tells us
/// which bucket a number belongs to, which is why `WindowClassifier` exists.
public enum QuotaWindowKind: String, Codable, CaseIterable, Sendable {
    /// 5 hour rolling session window.
    case session
    /// 7 day rolling window (called "week" everywhere in the UI).
    case weekly

    /// Short label for compact rows.
    public var shortLabel: String {
        switch self {
        case .session: return "5h"
        case .weekly: return "Week"
        }
    }
}

/// A single quota bucket.
public struct QuotaWindow: Codable, Equatable, Sendable {
    /// Session or weekly.
    public var kind: QuotaWindowKind
    /// Consumed quota in percent, 0...100. Values are clamped by the parsers.
    public var usedPercent: Double
    /// Moment the bucket rolls over, when the provider tells us.
    public var resetsAt: Date?
    /// Length of the rolling window in seconds, when the provider tells us.
    public var windowLength: TimeInterval?
    /// Set for model scoped limits, e.g. Claude's "Opus" weekly bucket.
    public var scope: String?

    public init(kind: QuotaWindowKind,
                usedPercent: Double,
                resetsAt: Date? = nil,
                windowLength: TimeInterval? = nil,
                scope: String? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowLength = windowLength
        self.scope = scope
    }

    /// Remaining quota in percent, clamped to 0...100.
    public var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

/// Maps a provider supplied window length onto a known bucket.
///
/// Codex reports `limit_window_seconds`; Claude does not always tell us the
/// length at all, hence the nil tolerant signature. Tolerances are deliberately
/// wide: providers have shipped 17_999 s and 604_799 s values in the past.
public enum WindowClassifier {
    public static let sessionSeconds = 18_000          // 5 h
    public static let weeklySeconds = 604_800          // 7 d

    /// Returns nil when the length matches neither bucket.
    public static func kind(forSeconds seconds: Int?) -> QuotaWindowKind? {
        guard let seconds, seconds > 0 else { return nil }
        if abs(seconds - sessionSeconds) <= 3_600 { return .session }
        if abs(seconds - weeklySeconds) <= 86_400 { return .weekly }
        return nil
    }

    /// Assigns two raw windows to buckets, falling back to the API's own
    /// ordering (primary = session, secondary = weekly) when the length is
    /// missing or unrecognised.
    public static func buckets(primary: (seconds: Int?, window: QuotaWindow)?,
                               secondary: (seconds: Int?, window: QuotaWindow)?)
    -> (session: QuotaWindow?, weekly: QuotaWindow?) {
        var session: QuotaWindow?
        var weekly: QuotaWindow?

        func place(_ entry: (seconds: Int?, window: QuotaWindow), fallback: QuotaWindowKind) {
            switch kind(forSeconds: entry.seconds) ?? fallback {
            case .session:
                if session == nil { session = entry.window } else if weekly == nil { weekly = entry.window }
            case .weekly:
                if weekly == nil { weekly = entry.window } else if session == nil { session = entry.window }
            }
        }

        if let primary { place(primary, fallback: .session) }
        if let secondary { place(secondary, fallback: .weekly) }
        return (session, weekly)
    }
}

// MARK: - Usage

/// Everything we know about one provider after a successful fetch.
public struct ServiceUsage: Codable, Equatable, Sendable {
    public var service: Service
    /// Plan name reported by the provider, e.g. "prolite" or "max".
    public var plan: String?
    /// Account e-mail, when the credentials expose it.
    public var account: String?
    /// 5 hour bucket.
    public var session: QuotaWindow?
    /// Weekly bucket.
    public var weekly: QuotaWindow?
    /// Extra buckets such as Claude's model scoped weekly limits.
    public var scoped: [QuotaWindow]
    /// When the data was fetched (not when it was cached).
    public var fetchedAt: Date
    /// Free-form diagnostics, e.g. "credits balance 0".
    public var notes: [String]

    public init(service: Service,
                plan: String? = nil,
                account: String? = nil,
                session: QuotaWindow? = nil,
                weekly: QuotaWindow? = nil,
                scoped: [QuotaWindow] = [],
                fetchedAt: Date = Date(),
                notes: [String] = []) {
        self.service = service
        self.plan = plan
        self.account = account
        self.session = session
        self.weekly = weekly
        self.scoped = scoped
        self.fetchedAt = fetchedAt
        self.notes = notes
    }

    public func window(_ kind: QuotaWindowKind) -> QuotaWindow? {
        switch kind {
        case .session: return session
        case .weekly: return weekly
        }
    }

    /// Highest used percentage across all buckets, used for colour coding.
    public var maxUsedPercent: Double {
        [session, weekly].compactMap { $0?.usedPercent }.max() ?? 0
    }
}

// MARK: - Result wrapper

/// Result of refreshing a single provider: either fresh usage, or the reason
/// the last attempt failed. `usage` is kept when a refresh fails so the menu bar
/// can keep showing the last known numbers with a warning mark.
public struct ServiceResult: Codable, Equatable, Sendable {
    public var usage: ServiceUsage?
    public var errorCode: String?
    public var errorDetail: String?

    public init(usage: ServiceUsage? = nil, errorCode: String? = nil, errorDetail: String? = nil) {
        self.usage = usage
        self.errorCode = errorCode
        self.errorDetail = errorDetail
    }

    public var isOK: Bool { errorCode == nil }
}

/// Full state of the app: one result per service plus the refresh timestamp.
///
/// Encoded as JSON to `~/Library/Application Support/UsageBar/snapshot.json` so
/// a freshly launched app can paint numbers immediately instead of blanks.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var results: [Service: ServiceResult]
    public var updatedAt: Date

    public init(results: [Service: ServiceResult] = [:], updatedAt: Date = Date()) {
        self.results = results
        self.updatedAt = updatedAt
    }

    public func result(for service: Service) -> ServiceResult? { results[service] }

    // MARK: - Codable

    // `[Service: …]` would otherwise be encoded by Foundation as a flat array of
    // alternating keys and values. Custom coding keeps snapshot.json readable:
    //   { "results": { "codex": {…}, "claude": {…} }, "updatedAt": "…" }
    private enum CodingKeys: String, CodingKey {
        case results
        case updatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let byName = Dictionary(uniqueKeysWithValues: results.map { ($0.key.rawValue, $0.value) })
        try container.encode(byName, forKey: .results)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let byName = try container.decode([String: ServiceResult].self, forKey: .results)

        var mapped: [Service: ServiceResult] = [:]
        for (name, result) in byName {
            guard let service = Service(rawValue: name) else { continue }
            mapped[service] = result
        }
        self.results = mapped
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Errors

/// Errors surfaced by providers. Rendered to the user through
/// `Localization.describe(_:)`, so every case needs a friendly sentence.
public enum UsageError: Error, Equatable, Sendable {
    /// Credentials not found. Payload is the hint about how to create them.
    case credentialsMissing(String)
    /// Credentials exist but are past their expiry timestamp.
    case credentialsExpired(Date?)
    /// HTTP 401 – token revoked or wrong account.
    case unauthorized
    /// HTTP 403 – usually region/bot blocking in front of chatgpt.com.
    case blocked
    /// HTTP 429 – polled too often.
    case rateLimited
    /// Any other HTTP status.
    case http(Int)
    /// Transport level failure (DNS, TLS, proxy down).
    case network(String)
    /// Response body did not look like what we expect.
    case decoding(String)

    /// Stable code persisted in the snapshot; keeps the JSON readable and
    /// avoids storing whole English sentences on disk.
    public var code: String {
        switch self {
        case .credentialsMissing: return "credentials_missing"
        case .credentialsExpired:  return "credentials_expired"
        case .unauthorized:        return "unauthorized"
        case .blocked:             return "blocked"
        case .rateLimited:         return "rate_limited"
        case .http(let status):    return "http_\(status)"
        case .network:             return "network"
        case .decoding:            return "decoding"
        }
    }

    /// Rebuilds an error from a stored snapshot. The detail string carries the
    /// human readable part, so the round trip is lossy on purpose.
    public static func from(code: String) -> UsageError {
        switch code {
        case "credentials_missing": return .credentialsMissing("")
        case "credentials_expired": return .credentialsExpired(nil)
        case "unauthorized":        return .unauthorized
        case "blocked":             return .blocked
        case "rate_limited":        return .rateLimited
        case "network":             return .network("")
        case "decoding":            return .decoding("")
        default:
            if let status = Int(code.replacingOccurrences(of: "http_", with: "")) {
                return .http(status)
            }
            return .network(code)
        }
    }
}
