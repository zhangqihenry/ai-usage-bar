import Foundation

/// Reads Claude quota from the OAuth usage endpoint that Claude Code's `/usage`
/// command calls.
///
/// Endpoint: `GET https://api.anthropic.com/api/oauth/usage`
/// Auth:     Claude Code OAuth access token (Keychain or credentials file)
/// Header:   `anthropic-beta: oauth-2025-04-20` is mandatory
///
/// The response is documented only by reverse engineering, so the parser reads
/// both shapes seen in the wild:
///   * flat buckets `five_hour` / `seven_day` (older clients), and
///   * a `limits` array with `kind` = `session` / `weekly_all` (current clients).
///
/// `utilization` is a percentage (0...100), not a fraction. Values are clamped,
/// never rescaled: a reported `1.0` means one percent used.
public struct ClaudeProvider: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let userAgent = "claude-code/2.0.0"

    public init() {}

    public func fetch(using client: HTTPClient, now: Date = Date()) async throws -> ServiceUsage {
        let credentials = try ClaudeCredentialStore.load()
        if credentials.isExpired {
            throw UsageError.credentialsExpired(credentials.expiresAt)
        }

        let headers: [String: String] = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": Self.userAgent,
            "Content-Type": "application/json"
        ]

        let response = try await client.get(Self.endpoint, headers: headers)
        return try Self.parse(data: response.data,
                              subscriptionType: credentials.subscriptionType,
                              now: now)
    }

    // MARK: - Parsing

    struct Response: Decodable {
        struct Bucket: Decodable {
            var utilization: Double?
            var percent: Double?
            var resetsAt: String?

            /// Some responses name the timestamp `resets_at`, others `resetsAt`.
            enum CodingKeys: String, CodingKey {
                case utilization, percent
                case resetsAt = "resets_at"
            }

            enum AlternateKeys: String, CodingKey {
                case camelResetsAt = "resetsAt"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)
                percent = try container.decodeIfPresent(Double.self, forKey: .percent)
                resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
                if resetsAt == nil {
                    let alternate = try decoder.container(keyedBy: AlternateKeys.self)
                    resetsAt = try alternate.decodeIfPresent(String.self, forKey: .camelResetsAt)
                }
            }
        }

        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable {
                    var displayName: String?
                    var id: String?

                    enum CodingKeys: String, CodingKey {
                        case displayName = "display_name"
                        case id
                    }
                }
                var model: Model?
            }

            var kind: String?
            var percent: Double?
            var utilization: Double?
            var resetsAt: String?
            var scope: Scope?

            /// The live API sends `resets_at`; `resetsAt` is accepted as well so
            /// a casing change does not silently drop every reset time.
            enum CodingKeys: String, CodingKey {
                case kind, percent, utilization, scope
                case resetsAt = "resets_at"
            }

            enum AlternateKeys: String, CodingKey {
                case camelResetsAt = "resetsAt"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                kind = try container.decodeIfPresent(String.self, forKey: .kind)
                percent = try container.decodeIfPresent(Double.self, forKey: .percent)
                utilization = try container.decodeIfPresent(Double.self, forKey: .utilization)
                scope = try container.decodeIfPresent(Scope.self, forKey: .scope)
                resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
                if resetsAt == nil {
                    let alternate = try decoder.container(keyedBy: AlternateKeys.self)
                    resetsAt = try alternate.decodeIfPresent(String.self, forKey: .camelResetsAt)
                }
            }
        }

        /// Pay-as-you-go usage beyond the plan ("extra usage"), when enabled.
        struct ExtraUsage: Decodable {
            var isEnabled: Bool?
            var utilization: Double?

            enum CodingKeys: String, CodingKey {
                case isEnabled = "is_enabled"
                case utilization
            }
        }

        var fiveHour: Bucket?
        var sevenDay: Bucket?
        var sevenDayOpus: Bucket?
        var sevenDaySonnet: Bucket?
        var extraUsage: ExtraUsage?
        var limits: [Limit]?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
            case sevenDaySonnet = "seven_day_sonnet"
            case extraUsage = "extra_usage"
            case limits
        }
    }

    static func parse(data: Data,
                      subscriptionType: String?,
                      now: Date) throws -> ServiceUsage {
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UsageError.decoding("usage JSON did not match (\(HTTPClient.plainText(from: data, limit: 120)))")
        }

        // 1. Flat buckets are authoritative when present.
        var session = bucket(from: decoded.fiveHour, kind: .session)
        var weekly = bucket(from: decoded.sevenDay, kind: .weekly)

        // 2. Fill gaps from the structured `limits` array.
        var scoped: [QuotaWindow] = []
        for limit in decoded.limits ?? [] {
            let value = limit.percent ?? limit.utilization
            guard let value else { continue }
            let bucket = QuotaWindow(
                kind: classify(kind: limit.kind),
                usedPercent: max(0, min(100, value)),
                resetsAt: ISO8601.parse(limit.resetsAt),
                windowLength: nil,
                scope: limit.scope?.model?.displayName ?? limit.scope?.model?.id
            )

            if bucket.scope != nil {
                scoped.append(bucket)
            } else if bucket.kind == .session, session == nil {
                session = bucket
            } else if bucket.kind == .weekly, weekly == nil {
                weekly = bucket
            }
        }

        // 3. Per-model weekly buckets from the legacy flat fields.
        for (bucket, name) in [(decoded.sevenDayOpus, "Opus"), (decoded.sevenDaySonnet, "Sonnet")] {
            guard let bucket, let window = self.bucket(from: bucket, kind: .weekly) else { continue }
            var copy = window
            copy.scope = name
            scoped.append(copy)
        }

        // 4. Extra usage, shown as one more scoped row while it is switched on.
        //    It is a monthly budget; `kind` only matters for the two main slots,
        //    so `.weekly` here is a placeholder, and there is no reset time.
        if let extra = decoded.extraUsage, extra.isEnabled == true, let value = extra.utilization {
            scoped.append(QuotaWindow(kind: .weekly,
                                      usedPercent: max(0, min(100, value)),
                                      scope: "Extra"))
        }

        guard session != nil || weekly != nil || !scoped.isEmpty else {
            throw UsageError.decoding("usage JSON contained no quota buckets")
        }

        return ServiceUsage(
            service: .claude,
            plan: subscriptionType,
            account: nil,
            session: session,
            weekly: weekly,
            scoped: scoped,
            fetchedAt: now,
            notes: []
        )
    }

    /// Maps the `kind` strings used by the structured limits array.
    static func classify(kind: String?) -> QuotaWindowKind {
        let lowered = (kind ?? "").lowercased()
        if lowered.contains("session") || lowered.contains("5h") || lowered.contains("five") {
            return .session
        }
        return .weekly
    }

    static func bucket(from raw: Response.Bucket?, kind: QuotaWindowKind) -> QuotaWindow? {
        guard let raw else { return nil }
        guard let value = raw.utilization ?? raw.percent else { return nil }
        return QuotaWindow(
            kind: kind,
            usedPercent: max(0, min(100, value)),
            resetsAt: ISO8601.parse(raw.resetsAt),
            windowLength: kind == .session ? TimeInterval(WindowClassifier.sessionSeconds)
                                           : TimeInterval(WindowClassifier.weeklySeconds)
        )
    }
}
