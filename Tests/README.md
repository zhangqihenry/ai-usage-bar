# Tests

A self-contained test executable, because XCTest ships with Xcode and this
project is buildable with Command Line Tools alone.

```bash
swift run UsageBarSelfTest
```

`swift test` is not used and will not work without Xcode — if you are tempted to
"fix" that, read the comment at the top of `Package.swift` first.

| Path | Contents |
|---|---|
| [UsageBarCoreTests/Harness.swift](UsageBarCoreTests/Harness.swift) | ~100 lines: `suite`, `check`, `expectEqual`, `expectNotNil`, `expectError`, counters, exit code. |
| `UsageBarCoreTests/main.swift` | Entry point; calls one `run()` per suite. |
| `UsageBarCoreTests/CodexProviderTests.swift` | Codex parser + window classification. |
| `UsageBarCoreTests/ClaudeProviderTests.swift` | Claude parser, both response shapes, timestamp formats. |
| `UsageBarCoreTests/FormattingTests.swift` | Countdowns, bars, title layout, severity, settings clamping, snapshot JSON shape. |
| `UsageBarCoreTests/Fixtures/` | Raw JSON responses, copied into the bundle as resources. |

Adding a suite: create `FooTests.swift` with `enum FooTests { static func run() }`,
call it from `main.swift`, and keep fixtures as files rather than inline strings.
