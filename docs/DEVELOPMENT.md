# Development

## Toolchain

- macOS 13+ with **Command Line Tools**: `xcode-select --install`.
- Xcode is **not** required. Nothing here uses an `.xcodeproj`, Interface
  Builder, or XCTest.
- Swift 5.9+ (the toolchain that ships with the Command Line Tools is enough).

## Everyday commands

```bash
make build     # swift build (debug)
make test      # swift run UsageBarSelfTest
make app       # dist/UsageBar.app (release + ad-hoc signature)
make run       # build, kill the running copy, launch
make icon      # regenerate Resources/AppIcon.icns
make lint      # tabs / trailing whitespace check
make clean
```

`swift build` alone compiles both targets but produces a bare executable, not a
menu bar capable bundle. Use `make app` when you want to click on something.

## Tests

`swift test` is not used: XCTest lives inside Xcode and this project promises to
build without it. Instead `Tests/` holds an executable target with a ~100 line
harness (`Harness.swift`) and three suites.

```bash
swift run UsageBarSelfTest
```

Output is grouped by suite, with a `N checks, M failure(s)` summary and exit code
1 on failure, so it works as a CI step. `@testable import` works because the
suite runs in a debug build; do not run it in release.

Adding a test:

1. Open the suite that owns the behaviour (parsing / formatting).
2. Write a `private static func` and call it from `run()`.
3. Use `expectEqual`, `check`, `expectNotNil`, `expectError`.

Fixtures live in `Tests/UsageBarCoreTests/Fixtures/` and are copied into the
bundle verbatim (`Bundle.module`). Add a new JSON file there rather than pasting
a string into Swift.

## Debugging the app

A menu bar app has nowhere to print. Enable the log:

```bash
USAGEBAR_DEBUG=1 /path/to/UsageBar.app/Contents/MacOS/UsageBar
tail -f ~/Library/Application\ Support/UsageBar/usagebar.log
```

It records the launch, each refresh outcome (`codex=42% claude=blocked`), and
every render with the exact title string and the button frame — the frame is how
you tell a layout bug from a menu-bar-space problem.

Headless check of the data path:

```bash
UsageBar --print            # human readable, exit 2 if a service failed
USAGEBAR_LANG=en UsageBar --print
```

Run the app against throwaway state while testing:

```bash
USAGEBAR_HOME=/tmp/usagebar-dev UsageBar --print
```

## The menu bar item is not visible

Usually not a bug: either the menu bar is full (macOS parks overflow items
off-screen) or a manager such as Ice/Bartender keeps new items in its hidden
section. Confirm with the window list before touching drawing code:

```bash
# layer 25 windows within 60 pt of the top are status items
# negative x  = off-screen (hidden by a manager or overflowed)
# x > screen  = parked to the right
```

Quit the manager and the largest status-item app for one screenshot, then
relaunch both. `docs/TROUBLESHOOTING.md` has the exact commands.

## Adding a provider

1. Add a case to `Service` in `Models.swift` (raw value is the JSON key in
   `snapshot.json`, so pick it once and keep it).
2. Write `MyProvider.swift` in `Sources/UsageBarCore/` conforming to the same
   shape as the existing ones: `fetch(using:now:)` plus a `static parse` that the
   tests can call with a fixture.
3. Map whatever the vendor returns onto `ServiceUsage.session` / `.weekly` using
   `WindowClassifier` when the response includes a window length.
4. Convert failures into `UsageError` so the UI can translate them; add the new
   strings to `Localization.swift`.
5. Register it in `UsageService.refresh` and add a `showX` toggle in
   `AppSettings`, `SettingsView` and `MenuBarTitle`.
6. Add a fixture + suite; add the credential discovery to `Credentials.swift`.

A provider must never write to the vendor's credential store and must never block
the main thread.

## Release checklist

1. Bump `VERSION` and add a `CHANGELOG.md` entry.
2. `make test && make app`.
3. Launch the bundle, open the menu, check both services and one failure state
   (e.g. rename `~/.codex/auth.json` temporarily).
4. `scripts/build-app.sh` embeds the version and the git commit count as the
   bundle version; nothing else to edit.
5. Tag: `git tag v$(cat VERSION) && git push --tags`.
