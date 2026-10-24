import AppKit

/// Manages a per-user LaunchAgent so the app starts with the session.
///
/// A LaunchAgent is used instead of `SMAppService` because the app is shipped as
/// an ad-hoc signed, unnotarised bundle: `SMAppService.mainApp` refuses to
/// register bundles outside `/Applications` and its errors are opaque. Writing a
/// plist is transparent and easy for a user to inspect or delete.
///
/// The plist is only written or deleted, never loaded into launchd by hand:
///   * `launchctl bootstrap` honours `RunAtLoad` and would start a second copy
///     right next to the one the user is clicking in;
///   * `launchctl bootout` stops the job's process, which is this very app when
///     it was started at login.
/// launchd reads `~/Library/LaunchAgents` at the next login, which is exactly
/// when the setting is meant to take effect.
enum LaunchAtLogin {
    /// Must match `CFBundleIdentifier` in scripts/build-app.sh.
    static let label = "io.github.zhangqihenry.ai-usage-bar"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Writes the plist. Errors are surfaced to the caller so the menu can show
    /// an alert instead of failing silently.
    static func enable() throws {
        guard let executable = Bundle.main.executablePath else {
            throw NSError(domain: label, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot locate the app executable"])
        }
        try write(executable: executable)
    }

    static func disable() throws {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func toggle() throws {
        if isEnabled { try disable() } else { try enable() }
    }

    /// Re-points an existing LaunchAgent at this copy of the app when the bundle
    /// was moved or reinstalled elsewhere (e.g. from `dist/` to
    /// `/Applications`), so login does not launch a stale path. Only a real
    /// `.app` bundle is allowed to claim the agent; a bare `swift run` binary is
    /// not.
    static func repairIfNeeded() {
        guard isEnabled,
              Bundle.main.bundlePath.hasSuffix(".app"),
              let executable = Bundle.main.executablePath,
              registeredExecutable() != executable else { return }
        try? write(executable: executable)
    }

    /// `ProgramArguments[0]` of the installed plist.
    static func registeredExecutable() -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else { return nil }
        return arguments.first
    }

    private static func write(executable: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
    }
}
