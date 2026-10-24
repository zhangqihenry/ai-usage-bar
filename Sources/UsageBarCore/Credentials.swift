import Foundation

// MARK: - Codex

/// Credentials extracted from Codex's own auth file.
///
/// Codex CLI, the Codex desktop app and the ChatGPT desktop app share
/// `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`). The file is written by
/// OpenAI's tooling; this app only ever reads it.
public struct CodexCredentials: Equatable, Sendable {
    public let accessToken: String
    public let accountID: String?
    public let email: String?
    public let expiresAt: Date?
    public let authMode: String?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60 // 60 s safety margin
    }
}

/// Locates and parses Codex credentials.
public enum CodexCredentialStore {
    /// `$CODEX_HOME/auth.json`, else `~/.codex/auth.json`.
    public static var authFileURL: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
                .appendingPathComponent("auth.json")
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/auth.json")
    }

    /// Throws `UsageError.credentialsMissing` with an actionable hint when the
    /// file is absent, or `.decoding` when it exists but has an unexpected shape.
    public static func load() throws -> CodexCredentials {
        let url = authFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageError.credentialsMissing(
                "~/.codex/auth.json not found. Sign in with Codex or the ChatGPT desktop app first."
            )
        }

        guard let data = try? Data(contentsOf: url),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageError.decoding("auth.json is not valid JSON")
        }

        let tokens = root["tokens"] as? [String: Any]
        guard let accessToken = tokens?["access_token"] as? String, !accessToken.isEmpty else {
            // An API-key-only setup cannot read ChatGPT subscription quota:
            // the endpoint is tied to the OAuth session.
            if root["OPENAI_API_KEY"] is String {
                throw UsageError.credentialsMissing(
                    "auth.json only contains an API key. Run `codex login` to create a ChatGPT session."
                )
            }
            throw UsageError.decoding("auth.json has no tokens.access_token")
        }

        return CodexCredentials(
            accessToken: accessToken,
            accountID: tokens?["account_id"] as? String,
            email: JWT.email(of: accessToken),
            expiresAt: JWT.expiry(of: accessToken),
            authMode: root["auth_mode"] as? String
        )
    }
}

// MARK: - Claude

/// Credentials for the Claude Code OAuth session.
public struct ClaudeCredentials: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    /// `subscriptionType` from the credential blob, e.g. "max".
    public let subscriptionType: String?
    public let expiresAt: Date?
    /// Where the token came from, for diagnostics: "env", "file" or "keychain".
    public let source: String

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

/// Locates and parses Claude Code credentials.
///
/// Resolution order, first hit wins:
///   1. `CLAUDE_CODE_OAUTH_TOKEN` environment variable (CI / scripted setups).
///   2. `~/.claude/.credentials.json` (Linux, and macOS when present).
///   3. Keychain item "Claude Code-credentials" (macOS default install).
///
/// Reading the Keychain item goes through `/usr/bin/security`, which triggers
/// macOS' "allow access" prompt the first time. Clicking "Always Allow" grants
/// the app permanent access; rebuilding the app invalidates that grant.
public enum ClaudeCredentialStore {
    public static var credentialsFileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.credentials.json")
    }

    private static let keychainService = "Claude Code-credentials"

    public static func load() throws -> ClaudeCredentials {
        if let raw = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !raw.isEmpty {
            return ClaudeCredentials(
                accessToken: raw,
                refreshToken: nil,
                subscriptionType: nil,
                expiresAt: JWT.expiry(of: raw),
                source: "env"
            )
        }

        if let data = try? Data(contentsOf: credentialsFileURL),
           let credentials = parse(data: data, source: "file") {
            return credentials
        }

        if let data = keychainData(), let credentials = parse(data: data, source: "keychain") {
            return credentials
        }

        throw UsageError.credentialsMissing(
            "No Claude Code credentials found. Install Claude Code and sign in once (`claude`), "
            + "or export CLAUDE_CODE_OAUTH_TOKEN."
        )
    }

    /// Extracts the OAuth block from either credential container shape:
    /// `{"claudeAiOauth": {...}}` or the OAuth object itself.
    static func parse(data: Data, source: String) -> ClaudeCredentials? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let oauth = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }

        // `expiresAt` is epoch milliseconds in Claude Code's format.
        var expiry: Date?
        if let millis = oauth["expiresAt"] as? Double {
            expiry = Date(timeIntervalSince1970: millis / 1000)
        } else if let millis = oauth["expiresAt"] as? Int {
            expiry = Date(timeIntervalSince1970: Double(millis) / 1000)
        } else if let expiresIn = oauth["expiresIn"] as? Double {
            expiry = Date(timeIntervalSinceNow: expiresIn)
        }

        return ClaudeCredentials(
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            subscriptionType: oauth["subscriptionType"] as? String,
            expiresAt: expiry,
            source: source
        )
    }

    /// Reads the generic password item through the `security` helper.
    /// Returns nil when the item does not exist or the user denied access.
    static func keychainData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let trimmed = Data(String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        return trimmed.isEmpty ? nil : trimmed
    }
}
