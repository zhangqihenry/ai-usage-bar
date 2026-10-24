# UsageBarCore

Pure logic. No AppKit, no SwiftUI, no global state — everything here runs in the
test executable and would run on a server.

| File | Responsibility |
|---|---|
| `Models.swift` | `Service`, `QuotaWindow`, `ServiceUsage`, `ServiceResult`, `UsageSnapshot`, `UsageError`, and `WindowClassifier` (turns window length into 5 h / week). |
| `Credentials.swift` | Finds and parses Codex's `auth.json` and Claude's OAuth credentials (env → file → Keychain via `security`). Read-only, never refreshes. |
| `JWT.swift` | Signature-less JWT payload decoding, used only for the account e-mail and expiry. |
| `HTTPClient.swift` | One `URLSession` per proxy configuration, GET + JSON helpers, maps HTTP status codes to `UsageError`. |
| `CodexProvider.swift` | ChatGPT/Codex quota endpoint and its tolerant parser. |
| `ClaudeProvider.swift` | Anthropic OAuth usage endpoint; understands both the flat bucket shape and the newer `limits` array. |
| `UsageService.swift` | Actor that decides what to refresh, throttles per service, runs providers in parallel, merges with the previous snapshot, persists. |
| `SnapshotStore.swift` | Reads/writes `snapshot.json`. |
| `Settings.swift` | `AppSettings`, `ProxyConfiguration`, clamping, and the JSON settings store. |
| `MenuBarTitle.swift` | Snapshot + settings → `[TitleSegment]` (text + severity). Shared by the menu bar, tooltip, CLI and tests. |
| `Format.swift` | Percent, countdown (`2h13m`), clock, ASCII bar, title value formatting. |
| `Localization.swift` | Chinese/English string table and error descriptions. |
| `AppPaths.swift` | `~/Library/Application Support/UsageBar/…`, overridable with `USAGEBAR_HOME`. |

Rules for this folder:

- No `import AppKit`. A colour, a font or an `NSImage` here is a design error.
- Parsers must be `static` and take `Data` + `now`, so tests never need a network
  or a wall clock.
- New user visible strings go into `Localization.swift` with both languages.
