# scripts

| Script | What it does | When to run it |
|---|---|---|
| `build-app.sh` | `swift build -c release`, assembles `dist/UsageBar.app` (binary, generated `Info.plist`, icon), ad-hoc signs it. Honours `CONFIG=debug` and `BUILD_NUMBER`. | Every time you want a clickable app. `make app` calls it. |
| `install.sh` | Builds, quits the running copy, copies the bundle to `/Applications` (or `~/Applications` when not writable), launches it. `--login` hints at enabling auto start. | First install on a machine. |
| `uninstall.sh` | Unloads and deletes the LaunchAgent, quits the app, removes the bundle. `--purge` also deletes `~/Library/Application Support/UsageBar`. | Removing the app. |
| `make-icon.swift` | Draws the icon with AppKit at ten sizes, builds an `.iconset`, runs `iconutil`. Output defaults to `Resources/AppIcon.icns`. | After changing the artwork. `make icon`. |

Conventions:

- `set -euo pipefail` in every script; unknown arguments exit 64 rather than being
  ignored.
- The bundle identifier is `io.github.zhangqihenry.ai-usage-bar` and must stay in
  sync across `build-app.sh`, `LaunchAtLogin.swift` and `uninstall.sh` — the
  LaunchAgent label is how login start is found and removed.
- No script writes outside `dist/`, `/Applications`, `~/Applications` or
  `~/Library/LaunchAgents` without saying so in its header.
