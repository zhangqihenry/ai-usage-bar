import AppKit

/// Manages a per-user LaunchAgent so the app starts with the session.
///
/// A LaunchAgent is used instead of `SMAppService` because the app is shipped as
/// an ad-hoc signed, unnotarised bundle: `SMAppService.mainApp` refuses to
/// register bundles outside `/Applications` and its errors are opaque. Writing a
/// plist is transparent and easy for a user to inspect or delete.
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

    /// Writes the plist and loads it immediately. Errors are surfaced to the
    /// caller so the menu can show an alert instead of failing silently.
    static func enable() throws {
        guard let executable = Bundle.main.executablePath else {
            throw NSError(domain: label, code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot locate the app executable"])
        }

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

        // Best effort: if bootstrap fails (already loaded, sandbox oddities) the
        // plist still takes effect at the next login.
        launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    static func disable() throws {
        launchctl(["bootout", "gui/\(getuid())", plistURL.path])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func toggle() throws {
        if isEnabled { try disable() } else { try enable() }
    }

    private static func launchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}
