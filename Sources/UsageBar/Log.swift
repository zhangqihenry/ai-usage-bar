import Foundation
import UsageBarCore

/// Optional file logging. Off by default; enable with `USAGEBAR_DEBUG=1`:
///
///     USAGEBAR_DEBUG=1 open -a UsageBar --args --print   # CLI
///     USAGEBAR_DEBUG=1 /Applications/UsageBar.app/Contents/MacOS/UsageBar
///
/// The log lands in `~/Library/Application Support/UsageBar/usagebar.log` and is
/// trimmed to the last 200 KB on launch. A menu bar app has nowhere to show a
/// stack trace, so this is the only way a user can hand over diagnostics.
enum Log {
    static let isEnabled = ProcessInfo.processInfo.environment["USAGEBAR_DEBUG"] == "1"

    private static let maxBytes = 200 * 1024

    static func debug(_ message: String) {
        guard isEnabled else { return }
        let line = "[\(timestamp())] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))

        try? AppPaths.ensureSupportDirectory()
        let url = AppPaths.logFile
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Truncates the log if it grew past the cap. Called once at launch.
    static func trimIfNeeded() {
        let url = AppPaths.logFile
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
              size > maxBytes else { return }
        let empty = Data()
        try? empty.write(to: url)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func timestamp() -> String {
        formatter.string(from: Date())
    }
}
