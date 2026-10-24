# UsageBarCoreTests

| File | Tests |
|---|---|
| `Harness.swift` | The test framework itself: assertions, suite headers, summary, exit code. |
| `main.swift` | Entry point, one call per suite. |
| `CodexProviderTests.swift` | Weekly-only plans, two-window plans, clamping, reset precedence, unknown window lengths, malformed JSON. |
| `ClaudeProviderTests.swift` | Flat buckets, structured `limits`, scoped model buckets, empty response, timestamp parsing, kind mapping. |
| `FormattingTests.swift` | Countdown buckets, bar width, percent rounding, menu bar title variants, severity thresholds, settings clamping, proxy dictionary, snapshot JSON round trip. |
| `ServiceTests.swift` | Refresh pacing with an injected fetcher (kept numbers, 429 backoff, network retries), settings forward compatibility, credential parsing, classifier slot labels, Codex windows without a percent, staleness, threshold alerts, Claude extra usage. |
| `Fixtures/` | Response bodies. See [Fixtures/README.md](Fixtures/README.md). |

The suite runs in a **debug** build (`@testable import` needs it). Release builds
strip testability, so `swift run -c release UsageBarSelfTest` will fail to
compile; that is expected and CI uses debug.
