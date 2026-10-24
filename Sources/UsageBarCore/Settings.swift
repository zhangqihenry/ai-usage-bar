import Foundation

// MARK: - Proxy

/// How outbound requests reach the internet.
///
/// This matters a lot in practice: `chatgpt.com` refuses connections from
/// mainland China and Hong Kong, so the app has to be able to ride a local
/// proxy (Clash, Surge, sing-box ...) exactly like a browser would.
public struct ProxyConfiguration: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Follow the macOS system proxy settings (default).
        case system
        /// Ignore every proxy, connect directly.
        case direct
        /// Use the host/port below.
        case manual
    }

    public enum Scheme: String, Codable, CaseIterable, Sendable {
        case http
        case socks5
    }

    public var mode: Mode = .system
    public var scheme: Scheme = .http
    public var host: String = "127.0.0.1"
    /// 7897 is Clash Verge's default mixed port; a common sense default that the
    /// settings window shows as a hint rather than a requirement.
    public var port: Int = 7897

    public init(mode: Mode = .system, scheme: Scheme = .http, host: String = "127.0.0.1", port: Int = 7897) {
        self.mode = mode
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    private enum CodingKeys: String, CodingKey {
        case mode, scheme, host, port
    }

    /// Missing or unreadable keys fall back to their defaults, so a settings file
    /// written by an older (or newer) release still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProxyConfiguration()
        mode = container.lenient(Mode.self, .mode) ?? defaults.mode
        scheme = container.lenient(Scheme.self, .scheme) ?? defaults.scheme
        host = container.lenient(String.self, .host) ?? defaults.host
        port = container.lenient(Int.self, .port) ?? defaults.port
    }

    /// Dictionary handed to `URLSessionConfiguration.connectionProxyDictionary`.
    /// `nil` means "let CFNetwork use the system settings".
    public var connectionProxyDictionary: [AnyHashable: Any]? {
        switch mode {
        case .system:
            return nil
        case .direct:
            // Explicitly disabling every proxy key is the only reliable way to
            // stop CFNetwork from falling back to the system configuration.
            return [
                "HTTPEnable": 0,
                "HTTPSEnable": 0,
                "SOCKSEnable": 0,
                "ProxyAutoConfigEnable": 0,
                "ProxyAutoDiscoveryEnable": 0
            ]
        case .manual:
            switch scheme {
            case .http:
                return [
                    "HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
                    "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port
                ]
            case .socks5:
                // CFNetwork resolves hostnames through the SOCKS server for
                // this key set, which is what a SOCKS5h style proxy needs.
                return ["SOCKSEnable": 1, "SOCKSProxy": host, "SOCKSPort": port]
            }
        }
    }

    /// Human readable description used in the menu ("System", "127.0.0.1:7897").
    public var summary: String {
        switch mode {
        case .system: return "System"
        case .direct: return "Direct"
        case .manual: return "\(scheme.rawValue)://\(host):\(port)"
        }
    }
}

// MARK: - Display options

/// Which buckets appear in the menu bar title.
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case both
    case session
    case weekly

    public var title: String {
        switch self {
        case .both: return "5h + Week"
        case .session: return "5h only"
        case .weekly: return "Week only"
        }
    }
}

/// Compact (`Cx 12/48`) or labelled (`Cx 12% / 48%`).
public enum TitleStyle: String, Codable, CaseIterable, Sendable {
    case compact
    case labeled
}

// MARK: - Settings

/// User preferences, persisted as JSON at `AppPaths.settingsFile`.
///
/// Stored as a plain file (not UserDefaults) so power users and AI assistants
/// can inspect and edit it with any text editor.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Polling interval in seconds. Clamped to [60, 3600] on save.
    public var refreshIntervalSeconds: Int = 300
    public var showCodex: Bool = true
    public var showClaude: Bool = true
    public var displayMode: DisplayMode = .both
    public var titleStyle: TitleStyle = .compact
    /// Show remaining quota instead of consumed quota.
    public var showRemaining: Bool = false
    /// Colour turns amber at or above this percentage.
    public var warnThreshold: Double = 70
    /// Colour turns red at or above this percentage.
    public var dangerThreshold: Double = 90
    public var proxy: ProxyConfiguration = ProxyConfiguration()
    /// Menu bar text size in points.
    public var fontSize: Double = 11
    /// Post a macOS notification when a window crosses the warning or danger
    /// threshold. Off by default: turning it on triggers the permission prompt.
    public var notifyOnThresholds: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case refreshIntervalSeconds, showCodex, showClaude, displayMode, titleStyle
        case showRemaining, warnThreshold, dangerThreshold, proxy, fontSize
        case notifyOnThresholds
    }

    /// Decodes key by key with per-field defaults. The synthesized decoder would
    /// reject a file that lacks any key, and `SettingsStore.load()` would then
    /// throw away every preference the moment a release adds a new field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        refreshIntervalSeconds = container.lenient(Int.self, .refreshIntervalSeconds)
            ?? defaults.refreshIntervalSeconds
        showCodex = container.lenient(Bool.self, .showCodex) ?? defaults.showCodex
        showClaude = container.lenient(Bool.self, .showClaude) ?? defaults.showClaude
        displayMode = container.lenient(DisplayMode.self, .displayMode) ?? defaults.displayMode
        titleStyle = container.lenient(TitleStyle.self, .titleStyle) ?? defaults.titleStyle
        showRemaining = container.lenient(Bool.self, .showRemaining) ?? defaults.showRemaining
        warnThreshold = container.lenient(Double.self, .warnThreshold) ?? defaults.warnThreshold
        dangerThreshold = container.lenient(Double.self, .dangerThreshold) ?? defaults.dangerThreshold
        proxy = container.lenient(ProxyConfiguration.self, .proxy) ?? defaults.proxy
        fontSize = container.lenient(Double.self, .fontSize) ?? defaults.fontSize
        notifyOnThresholds = container.lenient(Bool.self, .notifyOnThresholds) ?? defaults.notifyOnThresholds
    }

    /// Age after which a service's numbers count as stale: three polling
    /// intervals, never less than three of Claude's 240 s minimum gaps plus
    /// slack, so a short interval does not flag healthy Claude data.
    public var staleAfter: TimeInterval {
        max(Double(refreshIntervalSeconds), 300) * 3
    }

    /// Whether `service` is switched on in settings.
    public func isVisible(_ service: Service) -> Bool {
        service == .codex ? showCodex : showClaude
    }

    /// Clamps values that would otherwise break the UI. Called after decoding
    /// and whenever the settings window commits a change.
    public func normalized() -> AppSettings {
        var copy = self
        copy.refreshIntervalSeconds = max(60, min(3600, refreshIntervalSeconds))
        copy.warnThreshold = max(50, min(95, warnThreshold))
        copy.dangerThreshold = max(copy.warnThreshold + 1, min(100, dangerThreshold))
        copy.fontSize = max(9, min(16, fontSize))
        copy.proxy.port = max(1, min(65535, proxy.port))
        if copy.proxy.host.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.proxy.host = "127.0.0.1"
        }
        return copy
    }
}

extension KeyedDecodingContainer {
    /// `decodeIfPresent` that also swallows type mismatches (a hand edited
    /// `"port": "7897"`), so one bad value costs one field, not the whole file.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// Reads and writes `AppSettings`.
public struct SettingsStore {
    public init() {}

    /// Loads settings, falling back to defaults when the file is missing or
    /// corrupt. Corruption must never keep the app from launching.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: AppPaths.settingsFile),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded.normalized()
    }

    public func save(_ settings: AppSettings) throws {
        try AppPaths.ensureSupportDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings.normalized())
        try data.write(to: AppPaths.settingsFile, options: .atomic)
    }
}
