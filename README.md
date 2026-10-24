# AI Usage Bar

ChatGPT (Codex) and Claude quota, live in your macOS menu bar: the rolling
**5 hour** session window and the **weekly** window for both services, side by
side.

```
Cx 42/18   Cl 8/56
```

`Cx` = Codex, `Cl` = Claude. The first number is the 5 hour window, the second is
the week. Both are **percent used**, so 100 means the quota is gone. A dash means
your plan does not have that window (Codex Pro Lite has no 5 hour cap, for
example).

## 中文快速开始

1. 先确保至少一个客户端登录过：Codex 登录会生成 `~/.codex/auth.json`，Claude Code 登录会把凭证写进钥匙串。
2. `git clone` 之后执行 `make app`，然后 `open dist/UsageBar.app`，或者直接跑 `scripts/install.sh`。
3. 菜单栏出现 `Cx …/…  Cl …/…`；点开有每个窗口的进度条、重置倒计时和设置入口。
4. 在香港或内地使用 ChatGPT 需要代理，到「设置 → 网络 / 代理」里选「手动」，填本地端口（Clash 默认 `127.0.0.1:7897`）。

---

## What it does

- **Menu bar title** with per-service percentages, coloured amber at 70% and red
  at 90% (thresholds configurable), plus a `!` marker when a refresh fails.
- **Dropdown**: one row per window with an ASCII progress bar, used percentage,
  reset countdown, plan name, and any error in plain language.
- **Settings window** (⌘,): refresh interval, which windows to show, used vs
  remaining, per-service toggles, proxy mode, reset to defaults.
- **Launch at login** via a LaunchAgent you can inspect and delete.
- **Proxy aware**: system proxy, direct, or an explicit HTTP/SOCKS5 endpoint.
  Needed because `chatgpt.com` refuses connections from some regions.
- **Headless CLI** (`--print`, `--json`) that proves the data path without a GUI.
- **No telemetry.** The only network calls are the two vendor endpoints.

## Requirements

- macOS 13 (Ventura) or newer.
- Command Line Tools to build (`xcode-select --install`). Xcode is not required.
- At least one signed-in client:
  - **Codex / ChatGPT desktop** → `~/.codex/auth.json`
  - **Claude Code** → Keychain item `Claude Code-credentials`, or
    `~/.claude/.credentials.json`, or `$CLAUDE_CODE_OAUTH_TOKEN`

## Install

```bash
git clone https://github.com/zhangqihenry/ai-usage-bar.git
cd ai-usage-bar
make app                        # builds dist/UsageBar.app
open dist/UsageBar.app
```

Or install into `/Applications` in one step:

```bash
scripts/install.sh
```

Uninstall:

```bash
scripts/uninstall.sh            # keeps your settings
scripts/uninstall.sh --purge    # removes them too
```

## Menu bar layout

| Piece | Meaning |
|---|---|
| `Cx` / `Cl` | Service prefix, dimmed |
| first number | 5 hour rolling window, percent used |
| second number | 7 day rolling window, percent used |
| `–` | window not present on this plan |
| `!` | last refresh failed, hover for the reason |
| trailing `…` | a refresh is in flight |

Settings can switch the title to 5 hour only, week only, percentages with a `%`
sign, or remaining quota instead of used.

## CLI

```bash
UsageBar --print      # human readable report, exit 2 if a service failed
UsageBar --json       # the snapshot as JSON
UsageBar --version
```

Useful in scripts and CI, and the first thing to attach to a bug report.

## Where state lives

```
~/Library/Application Support/UsageBar/settings.json   your preferences
~/Library/Application Support/UsageBar/snapshot.json   last known numbers (no tokens)
~/Library/Application Support/UsageBar/usagebar.log    only written with USAGEBAR_DEBUG=1
```

## Project layout

```
Sources/UsageBarCore/   pure logic: credentials, HTTP, parsing, formatting, titles
Sources/UsageBar/       AppKit menu bar app + SwiftUI settings window
Tests/                  self test executable with JSON fixtures
scripts/                build, install, uninstall, icon generator
docs/                   architecture, data sources, development, troubleshooting
Resources/              AppIcon.icns
```

Every folder has its own `README.md` naming each file and what it is for, so a
contributor (or another AI agent) can land anywhere in the tree and know what is
there.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the pieces fit, concurrency, persistence
- [docs/DATA-SOURCES.md](docs/DATA-SOURCES.md) — the two endpoints, credentials, quirks
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — build, test, debug, adding a provider
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — the item is invisible, 403, expired token

## Status

Working and daily driven. The two quota endpoints are undocumented vendor
endpoints, so they can change without notice; the parsers are defensive and the
UI always says which state it is in rather than showing a stale number silently.

Not implemented yet:

- Token refresh. When a vendor token expires the app says so and asks you to
  reopen the vendor client, instead of minting tokens behind the vendor's back.
- Localisation beyond Chinese and English.

## License

MIT. See [LICENSE](LICENSE).
