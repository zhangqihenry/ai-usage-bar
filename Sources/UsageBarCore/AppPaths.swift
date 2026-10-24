import Foundation

/// Where the app keeps its own state. Everything lives inside
/// `~/Library/Application Support/UsageBar/` so uninstalling is a folder delete.
///
/// `USAGEBAR_HOME` overrides the root, which the test suite and the CLI
/// `--print` mode use to avoid touching the real user state.
public enum AppPaths {
    public static var supportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["USAGEBAR_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("UsageBar", isDirectory: true)
    }

    public static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    public static var snapshotFile: URL { supportDirectory.appendingPathComponent("snapshot.json") }
    public static var logFile: URL { supportDirectory.appendingPathComponent("usagebar.log") }

    /// Creates the support directory if needed. Called before any write.
    public static func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    /// Opens the folder in Finder (used by the settings window).
    public static func reveal() {
        NSWorkspaceShim.open(supportDirectory)
    }
}

/// Tiny wrapper so `AppPaths` can stay Foundation-only in tests.
enum NSWorkspaceShim {
    static func open(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        try? process.run()
    }
}
