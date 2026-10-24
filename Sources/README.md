# Sources

Two SwiftPM targets, split along one line: does this file need AppKit?

| Target | Contents | Depends on |
|---|---|---|
| [UsageBarCore](UsageBarCore/README.md) | Credential discovery, HTTP, JSON parsing, formatting, menu bar title layout. Foundation only. | nothing |
| [UsageBar](UsageBar/README.md) | `NSStatusItem`, menus, SwiftUI settings window, CLI entry point, LaunchAgent. | AppKit, SwiftUI, UsageBarCore |

The split is not cosmetic: `UsageBarCore` is what the test executable imports, so
it must never import AppKit or SwiftUI. If you need `NSColor` in Core, pass a
severity value instead and let the app map it (`TitleSegment.Severity` is the
working example).

Build products: `usagebar` (the app) and the `UsageBarCore` library.
