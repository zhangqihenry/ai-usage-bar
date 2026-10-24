# Contributing

Small, focused project. Two rules matter more than style: do not break the
credential files of the vendor CLIs, and do not make the app lie about its state.

## Getting set up

```bash
git clone https://github.com/zhangqihenry/ai-usage-bar.git
cd ai-usage-bar
make test        # 73 checks, no network required
make app         # dist/UsageBar.app
```

Command Line Tools are enough; Xcode is not needed and the project has no
`.xcodeproj` on purpose.

## Before opening a pull request

1. `make test` passes.
2. `make lint` passes (tabs and trailing whitespace).
3. The app still builds as a bundle: `make app`.
4. If you touched a parser, add or update a fixture in
   `Tests/UsageBarCoreTests/Fixtures/` — do not test against the live API.
5. If you touched the UI, say which of these you checked: menu bar title, menu
   rows, settings window, CLI output.

## Code rules

- `Sources/UsageBarCore` must not `import AppKit`. Need a colour? Return a
  severity and map it in the app.
- Parsers stay `static` and take `(data:now:)` so they are testable without a
  network or a clock.
- Every user visible string goes through `Localization.swift` with both Chinese
  and English. Never concatenate sentence fragments; use one format string.
- Comments explain *why*, not *what*. A non-obvious header, a magic 240 s floor,
  a fallback path — those earn a comment.
- New folder or new file? Add it to that folder's `README.md`. The docs are part
  of the deliverable, not an afterthought.

## What will not be merged

- Code that writes to `~/.codex/auth.json`, the Claude Keychain item, or performs
  OAuth refresh grants on the user's behalf.
- Telemetry, analytics, or any network call other than the two quota endpoints.
- Polling faster than the per-service floors (60 s Codex, 240 s Claude).
- Replacing the test harness with XCTest while the project still promises to
  build with Command Line Tools alone.

## Reporting a bug

Run `UsageBar --print` and paste the output with tokens removed, plus the
"更新于 …" line and the macOS version. If the menu bar item is invisible, mention
whether you run Ice, Bartender or similar — that is the usual cause and it is not
a bug in the app.
