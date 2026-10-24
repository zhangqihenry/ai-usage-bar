import Foundation
import UsageBarCore

/// Headless mode. `usagebar --print` refreshes once, prints what it found and
/// exits, which makes the app scriptable and gives bug reports something
/// reproducible to attach.
///
/// Exit codes:
///   0  every enabled service returned data
///   2  at least one enabled service failed
///   64 unknown flag
///   70 timeout
enum CLI {
    private static let knownFlags: Set<String> = ["--help", "-h", "--version", "--print", "--json"]

    /// True when the process was started with one of our flags. Finder launches
    /// pass `-psn_...` arguments, which are ignored.
    static var isRequested: Bool {
        !Set(CommandLine.arguments.dropFirst()).isDisjoint(with: knownFlags)
    }

    static func run() -> Never {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") {
            printHelp()
            exit(0)
        }
        if args.contains("--version") {
            print("usagebar \(version)")
            exit(0)
        }

        let settings = SettingsStore().load()
        let snapshot = fetchSnapshot(settings: settings)

        if args.contains("--json") {
            printJSON(snapshot)
        } else {
            printHuman(snapshot, settings: settings)
        }

        exit(exitCode(snapshot, settings: settings))
    }

    // MARK: - Fetch

    /// Runs one refresh and blocks the (single threaded) CLI until it finishes.
    /// A semaphore is used instead of `await` at top level so the code path stays
    /// identical on every Swift version we support.
    private static func fetchSnapshot(settings: AppSettings) -> UsageSnapshot {
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            let service = UsageService(settings: settings)
            box.value = await service.refresh(force: true)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 90) == .timedOut {
            FileHandle.standardError.write(Data("usagebar: refresh timed out after 90s\n".utf8))
            exit(70)
        }
        return box.value ?? UsageSnapshot()
    }

    /// Reference box so the value can cross the concurrency boundary without
    /// making the whole file generic over Sendable.
    private final class Box: @unchecked Sendable {
        var value: UsageSnapshot?
    }

    // MARK: - Output

    private static func printHuman(_ snapshot: UsageSnapshot, settings: AppSettings) {
        print("UsageBar \(version)  ·  \(Format.timestamp(snapshot.updatedAt))  ·  proxy \(settings.proxy.summary)")

        for service in Service.allCases {
            guard let result = snapshot.result(for: service) else { continue }

            var header = service.displayName
            if let plan = result.usage?.plan { header += "  (\(plan))" }
            if let account = result.usage?.account { header += "  \(account)" }
            print(header)

            if let usage = result.usage {
                for kind in QuotaWindowKind.allCases {
                    guard let window = usage.window(kind) else {
                        print("  \(kind.shortLabel.padding(toLength: 5, withPad: " ", startingAt: 0)) –")
                        continue
                    }
                    let resetText = window.resetsAt.map { "resets in \(Format.countdown(to: $0))" } ?? ""
                    print("  \(kind.shortLabel.padding(toLength: 5, withPad: " ", startingAt: 0))"
                          + " \(Format.bar(window.usedPercent)) "
                          + "\(Format.percent(window.usedPercent).leftPadded(to: 4))  \(resetText)")
                }
                for window in usage.scoped {
                    let name = window.scope ?? "model"
                    print("  \(name.padding(toLength: 5, withPad: " ", startingAt: 0))"
                          + " \(Format.bar(window.usedPercent)) "
                          + "\(Format.percent(window.usedPercent).leftPadded(to: 4))")
                }
            }

            if let code = result.errorCode {
                print("  ⚠︎  " + L.describe(code: code, detail: result.errorDetail))
            }
        }
    }

    private static func printJSON(_ snapshot: UsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot),
              let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("usagebar: cannot encode snapshot\n".utf8))
            exit(1)
        }
        print(text)
    }

    private static func exitCode(_ snapshot: UsageSnapshot, settings: AppSettings) -> Int32 {
        let enabled = Service.allCases.filter {
            $0 == .codex ? settings.showCodex : settings.showClaude
        }
        let failures = enabled.filter { snapshot.result(for: $0)?.isOK != true }
        return failures.isEmpty ? 0 : 2
    }

    private static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    private static func printHelp() {
        print("""
        usagebar \(version) — ChatGPT (Codex) and Claude quota in the macOS menu bar

        USAGE:
          usagebar              start the menu bar app
          usagebar --print      refresh once, print a human readable report, exit
          usagebar --json       refresh once, print the raw snapshot as JSON, exit
          usagebar --version    print the version
          usagebar --help       this text

        EXIT CODES:
          0  ok        2  one or more services failed        70  timeout

        CREDENTIALS:
          Codex   ~/.codex/auth.json          (sign in with Codex or ChatGPT desktop)
          Claude  Keychain "Claude Code-credentials" or ~/.claude/.credentials.json

        STATE:
          ~/Library/Application Support/UsageBar/   settings.json, snapshot.json
        """)
    }
}

private extension String {
    /// Right aligns a value inside a fixed width, used for the percent column.
    func leftPadded(to width: Int) -> String {
        let missing = max(0, width - count)
        return String(repeating: " ", count: missing) + self
    }
}
