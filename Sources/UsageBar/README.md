# UsageBar (app target)

AppKit and SwiftUI wiring. Nothing here parses JSON or reads Keychain — it asks
`UsageBarCore` for results and draws them.

| File | Responsibility |
|---|---|
| `main.swift` | Entry point. Handles CLI flags before creating any AppKit object, then boots `NSApplication` with `.accessory` policy. |
| `AppDelegate.swift` | Owns state: settings, snapshot, refresh timer, wake observer, settings window. `@MainActor`. |
| `StatusItemController.swift` | Creates the `NSStatusItem`, renders the attributed title from `MenuBarTitle.segments`, handles the click that pops the menu, builds the tooltip. |
| `MenuBuilder.swift` | Builds the dropdown: service sections, window rows with bars, error lines, actions. Also `ClosureMenuItem`, the closure-backed menu item. |
| `SettingsView.swift` | SwiftUI form + `SettingsModel` (bridges edits to the delegate) + `SettingsWindowController`. |
| `LaunchAtLogin.swift` | Writes/removes `~/Library/LaunchAgents/io.github.zhangqihenry.ai-usage-bar.plist` and bootstraps it. |
| `CLI.swift` | `--print`, `--json`, `--version`, `--help`; exit codes; human readable table. |
| `Log.swift` | `USAGEBAR_DEBUG=1` file logging with size cap. A menu bar app has no stderr. |

Conventions:

- Anything touching AppKit runs on the main actor. Network calls are awaited from
  `UsageService`, never performed inline here.
- The menu is rebuilt on every click through `menuProvider`; do not cache and
  mutate a single `NSMenu`.
- New settings fields must be added in three places: `AppSettings` (Core), this
  target's `SettingsView`, and whatever reads them (`MenuBarTitle`,
  `UsageService`).
