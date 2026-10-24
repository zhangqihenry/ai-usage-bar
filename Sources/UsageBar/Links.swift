import AppKit
import Foundation

/// External links the UI can open. Kept in one place so a fork can point them at
/// its own docs without hunting through the menu code.
enum Links {
    /// Setup guide: how to create the Codex and Claude credentials this app reads.
    /// Opened when a service reports `credentials_missing`, which is the single
    /// most common first-run problem.
    static let setup = URL(string: "https://github.com/zhangqihenry/ai-usage-bar/blob/main/docs/SETUP.md")!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
