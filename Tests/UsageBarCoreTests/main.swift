import Foundation

// Entry point for the self test executable: `swift run UsageBarSelfTest`.
//
// Suites live in sibling files, one per area (Codex parsing, Claude parsing,
// formatting). Add a new file, add one `run()` call here, done.

print("UsageBar self test")
CodexProviderTests.run()
ClaudeProviderTests.run()
FormattingTests.run()
ServiceTests.run()
runner.finish()
