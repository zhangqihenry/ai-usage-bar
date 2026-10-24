# Architecture

## Shape

```
                 ┌──────────────────────────────┐
                 │ Sources/UsageBar (AppKit)    │
                 │ main.swift  AppDelegate      │
                 │ StatusItemController         │
                 │ MenuBuilder   SettingsView   │
                 └──────────────┬───────────────┘
                                │ await
                 ┌──────────────▼───────────────┐
                 │ UsageService (actor)         │
                 │ refresh, throttle, merge,    │
                 │ persist                      │
                 └───┬──────────────────┬───────┘
        ┌────────────▼───┐   ┌──────────▼────────┐
        │ CodexProvider  │   │ ClaudeProvider    │
        │ + credentials  │   │ + credentials     │
        └────────┬───────┘   └──────────┬────────┘
                 └──────────┬───────────┘
                    ┌───────▼────────┐
                    │ HTTPClient     │  proxy policy lives here
                    └───────┬────────┘
                   vendor quotas endpoints
```

The app target holds **only** AppKit/SwiftUI wiring: it never parses JSON and
never touches Keychain. `UsageBarCore` is Foundation-only, which is why the whole
parsing layer can run in the self test executable without a window server.

## Refresh cycle

1. `applicationDidFinishLaunching` renders the cached snapshot from disk, then
   asks `UsageService` for a refresh.
2. `UsageService.refresh(force:)` decides which services are due. Each service
   has a hard floor (`codex` 60 s, `claude` 240 s) because Claude's endpoint rate
   limits aggressively; the user's interval can only be slower than the floor.
3. Both providers run in a `withTaskGroup`, so latency is the slower call, not
   the sum.
4. Results merge into the previous snapshot. **A failure keeps the old numbers**
   and stores an error code next to them; the title gains a `!` while the menu
   shows the reason. Blanking the menu bar on a flaky network would be worse than
   showing numbers that are five minutes old.
5. The merged snapshot is written to `snapshot.json` and the timer restarts, so
   the interval counts from the end of a fetch, not from the start.
6. The timer lives in `.common` run loop mode so it keeps firing while a menu is
   tracking, and the app refreshes on `NSWorkspace.didWakeNotification` and when
   the menu is opened after more than one interval.

## Concurrency

- `UsageService` is an `actor`: the timer, the menu click and the settings window
  can all ask for a refresh, and only one runs at a time. A second request while
  a fetch is in flight returns the current snapshot immediately.
- `AppDelegate` and the SwiftUI model are `@MainActor`. Network work is awaited,
  so the main thread never blocks on a proxy hop.
- `HTTPClient` is `@unchecked Sendable`: it holds an immutable `URLSession`
  configuration, which is safe to share across tasks.

## Rendering

`MenuBarTitle` (Core) turns a snapshot plus settings into `[TitleSegment]`, each
with a text run and a severity. The AppKit layer maps severity to `NSColor` and
builds an `NSAttributedString` with a monospaced-digit font so the title width
does not jitter as numbers change. Keeping the layout in Core means the CLI and
the tests use the same function the menu bar uses.

The dropdown is rebuilt on every click (`menuProvider`) rather than cached and
mutated, which removes a whole class of "the menu shows yesterday" bugs and lets
"Refresh Now" disable itself mid-flight.

## Persistence

Plain JSON under `~/Library/Application Support/UsageBar/`:

- `settings.json` — `AppSettings`, clamped on load and save. A corrupt file falls
  back to defaults; it must never prevent launch.
- `snapshot.json` — last `UsageSnapshot`, no credentials, no e-mail addresses
  beyond the account label the vendor returns.

`USAGEBAR_HOME` overrides the folder, which the tests use to avoid touching real
state.

## Deliberate decisions

- **No token refresh.** Both vendors rotate refresh tokens. A third-party app
  that refreshes quietly can invalidate the vendor CLI's session and log the user
  out. The app reports "session expired, reopen the client" instead.
- **Read-only credentials.** `~/.codex/auth.json` and the Claude Keychain item
  are only ever read.
- **Two windows, not a list.** Every plan seen so far exposes at most a 5 hour
  and a 7 day window. Window length decides the bucket, not JSON ordering, so a
  plan with only a weekly window still lands in the right column.
- **No AppKit in Core.** It is the difference between a test suite that runs with
  Command Line Tools and one that needs Xcode.
