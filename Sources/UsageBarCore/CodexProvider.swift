import Foundation

/// Reads ChatGPT / Codex quota from the same endpoint the Codex CLI's `/status`
/// command uses.
///
/// Endpoint: `GET https://chatgpt.com/backend-api/wham/usage`
/// Auth:     OAuth access token + `chatgpt-account-id` from `~/.codex/auth.json`
///
/// The response describes one or two rolling windows. Which bucket is the 5 hour
/// session is decided by `limit_window_seconds`, not by position: accounts on
/// the cheaper plans report a single 7 day window in `primary_window`.
/// This endpoint is undocumented and can change without notice; the parser is
/// therefore tolerant of missing fields and unknown window lengths.
public struct CodexProvider: Sendable {
    public static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    /// Codex CLI's own user agent. Using it keeps the request pattern identical
    /// to the official client.
    static let userAgent = "codex_cli_rs/0.60.0"

    public init() {}

    public func fetch(using client: HTTPClient, now: Date = Date()) async throws -> ServiceUsage {
        let credentials = try CodexCredentialStore.load()
        if credentials.isExpired {
            throw UsageError.credentialsExpired(credentials.expiresAt)
        }

        var headers: [String: String] = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "User-Agent": Self.userAgent,
            "originator": "codex_cli_rs",
            "Accept": "application/json"
        ]
        if let accountID = credentials.accountID {
            headers["chatgpt-account-id"] = accountID
        }

        let response = try await client.get(Self.endpoint, headers: headers)
        return try Self.parse(data: response.data,
                              emailFallback: credentials.email,
                              now: now)
    }

    // MARK: - Parsing (internal so the tests can drive it with fixtures)

    /// Wire format of `/backend-api/wham/usage`. Only the fields we display are
    /// modelled; the endpoint returns a lot more.
    struct Response: Decodable {
        struct Window: Decodable {
            var usedPercent: Double?
            var limitWindowSeconds: Int?
            var resetAt: Int?
            var resetAfterSeconds: Int?
            var remaining: Int?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case limitWindowSeconds = "limit_window_seconds"
                case resetAt = "reset_at"
                case resetAfterSeconds = "reset_after_seconds"
                case remaining
            }
        }

        struct RateLimit: Decodable {
            var allowed: Bool?
            var limitReached: Bool?
            var primaryWindow: Window?
            var secondaryWindow: Window?

            enum CodingKeys: String, CodingKey {
                case allowed
                case limitReached = "limit_reached"
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }
        }

        struct Credits: Decodable {
            var hasCredits: Bool?
            var unlimited: Bool?
            var balance: String?

            enum CodingKeys: String, CodingKey {
                case hasCredits = "has_credits"
                case unlimited
                case balance
            }
        }

        var email: String?
        var planType: String?
        var rateLimit: RateLimit?
        var credits: Credits?

        enum CodingKeys: String, CodingKey {
            case email
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case credits
        }
    }

    static func parse(data: Data, emailFallback: String?, now: Date) throws -> ServiceUsage {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UsageError.decoding("usage JSON did not match (\(HTTPClient.plainText(from: data, limit: 120)))")
        }

        guard let rateLimit = decoded.rateLimit else {
            throw UsageError.decoding("usage JSON has no rate_limit")
        }

        let primary = bucket(from: rateLimit.primaryWindow, now: now)
        let secondary = bucket(from: rateLimit.secondaryWindow, now: now)
        // Windows are reported but none carries a percentage: the format moved
        // under us, which deserves an error rather than an empty row.
        if primary == nil, secondary == nil,
           rateLimit.primaryWindow != nil || rateLimit.secondaryWindow != nil {
            throw UsageError.decoding("rate_limit windows have no used_percent")
        }
        let buckets = WindowClassifier.buckets(primary: primary, secondary: secondary)

        var notes: [String] = []
        if rateLimit.limitReached == true {
            notes.append("limit reached")
        }
        if let credits = decoded.credits, credits.hasCredits == true, let balance = credits.balance {
            notes.append("credits \(balance)")
        }

        return ServiceUsage(
            service: .codex,
            plan: decoded.planType,
            account: decoded.email ?? emailFallback,
            session: buckets.session,
            weekly: buckets.weekly,
            scoped: [],
            fetchedAt: now,
            notes: notes
        )
    }

    /// Converts one raw window into a `QuotaWindow`. Returns nil for an absent
    /// window (normal on plans that only have a weekly cap) and for a window
    /// without `used_percent`: showing "0%" for an unknown value would claim the
    /// whole quota is available.
    static func bucket(from window: Response.Window?,
                       now: Date) -> (seconds: Int?, window: QuotaWindow)? {
        guard let window, let usedPercent = window.usedPercent else { return nil }

        let percent = max(0, min(100, usedPercent))
        var resetsAt: Date?
        if let resetAt = window.resetAt, resetAt > 0 {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(resetAt))
        } else if let after = window.resetAfterSeconds, after > 0 {
            resetsAt = now.addingTimeInterval(TimeInterval(after))
        }

        // Kind is provisional; `WindowClassifier.buckets` re-assigns it based
        // on `limit_window_seconds` when that value is present.
        let provisional: QuotaWindowKind = (window.limitWindowSeconds ?? 0) > 86_400 ? .weekly : .session
        return (
            window.limitWindowSeconds,
            QuotaWindow(kind: provisional,
                        usedPercent: percent,
                        resetsAt: resetsAt,
                        windowLength: window.limitWindowSeconds.map(TimeInterval.init))
        )
    }
}
