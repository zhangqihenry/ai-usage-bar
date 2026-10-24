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

    public init() {}

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
