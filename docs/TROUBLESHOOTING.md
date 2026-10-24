# Troubleshooting

Start with the CLI: it uses the same credentials, the same proxy settings and the
same parsers as the app, but prints what happened.

```bash
/Applications/UsageBar.app/Contents/MacOS/UsageBar --print
```

Exit code `0` means every enabled service answered, `2` means at least one did
not, and the reason is printed on the failing line.

## The menu bar item is invisible

The app is probably running fine. Check whether the status item exists:

```bash
# list status item windows (layer 25, top of screen)
osascript -e 'tell application "System Events" to get name of every process whose name is "UsageBar"'
```

Then look at where its window sits. A negative `x` means it is off-screen:

- **A menu bar manager** (Ice, Bartender, Hidden Bar) put the new item in its
  hidden section. Open the manager and drag `UsageBar` into the always-visible
  section, or exempt it in the manager's settings.
- **The menu bar is full.** macOS parks overflow items off-screen. Hide or remove
  another item; a menu bar with 25 icons has no room for a 90 pt text item.
- **The screen is a shared/virtual display.** Menu bar extras render on the
  console display; a screenshot from a remote session can differ.

To confirm rendering during development, quit the manager and one large status
item app for a moment, capture, then relaunch both:

```bash
osascript -e 'tell application "Ice" to quit'
osascript -e 'tell application "Stats" to quit'
screencapture -x /tmp/shot.png
open -a Ice; open -a Stats
```

## `Cx –/0` — the 5 hour number is a dash

Not an error. Your plan does not expose a 5 hour window; Codex answers with a
single weekly window. The dash keeps the two services aligned. Use
"设置 → 菜单栏显示 → 仅周" if you would rather see one number.

## 403 / "请求被拒绝"

`chatgpt.com` blocks connections from some regions, including Hong Kong and
mainland China, and returns an HTML page instead of JSON. The app reports this as
`blocked`.

- Turn on your proxy, then either leave the mode on **System** (the app follows
  the macOS proxy settings) or set **Manual** with the local port —
  `127.0.0.1:7897` for Clash Verge's default mixed port.
- In Clash, make sure the node is outside the blocked region and that
  `chatgpt.com` actually goes through the proxy. In rule mode a subscription may
  send it DIRECT.
- Verify egress from the same network:
  `curl -x http://127.0.0.1:7897 https://api.ipify.org`

## 401 / "凭证被拒绝"

The token is valid JSON but rejected: signed out elsewhere, password changed, or
the token was revoked. Sign in again with the vendor client (`codex login`, or
open Claude Code). The app then picks up the new token on the next refresh.

## "登录已过期"

Access tokens are short lived. The app deliberately does **not** refresh them: a
refresh token is rotated by the grant, and spending it outside the vendor CLI can
sign you out of the CLI itself. Reopen Codex or Claude Code once; they refresh
and write the new token, and the next poll picks it up.

## "未找到登录凭证"

Nothing to read yet. [SETUP.md](SETUP.md) is the step-by-step version; the short
form:

- Codex: `~/.codex/auth.json` does not exist. Run `codex login` (Codex CLI) or
  sign in with the Codex desktop app. The plain ChatGPT desktop app does not
  create this file, and an `OPENAI_API_KEY`-only file is not enough — quota needs
  an OAuth session.
- Claude: no Keychain item `Claude Code-credentials`, no
  `~/.claude/.credentials.json`, no `$CLAUDE_CODE_OAUTH_TOKEN`. Install Claude
  Code (`npm i -g @anthropic-ai/claude-code`) and run `claude` once. The plain
  Claude desktop app does not create this credential.

Check the Keychain item exists:

```bash
security find-generic-password -s "Claude Code-credentials" >/dev/null && echo found
```

## A Keychain prompt appears

The app reads Claude's credential item through `/usr/bin/security`, so the
prompt (if any) asks on behalf of `security`. Choose **Always Allow**; that
trust is attached to the system tool, so rebuilding UsageBar does not reset it.
If nobody answers, the read gives up after 30 seconds and the Claude row says
"Timed out reading the Keychain item" instead of freezing every later refresh.

## Numbers look old / "showing data from … ago"

When a refresh fails the app keeps the last good numbers instead of blanking
the menu bar. Once they are older than three polling intervals (at least 15
minutes) they are drawn dimmed, the service gets a "showing data from 3h ago"
line, and the footer reads "Last checked … (some data is stale)". Fix the error
shown under that service and the next refresh brings live numbers back.

## 429 / "请求过于频繁"

The Claude usage endpoint limits calls per token window. The app already enforces
a 240 s floor for Claude and caches the last response. After a 429 it pauses
that service for 5 minutes, doubling on each consecutive 429 up to an hour; even
"Refresh Now" waits, and the error line shows the retry time. If it keeps
happening, raise the refresh interval in Settings. Numbers keep displaying from
the cache.

## Numbers look frozen

- Check the dropdown's "上次刷新 …" line; it turns amber when a service is
  showing kept, stale numbers.
- The app pauses polling while the machine sleeps and refreshes 5 s after wake.
  If the network is not back yet it retries after 30 s, 60 s, 120 s … up to the
  polling interval.
- `USAGEBAR_DEBUG=1` plus `~/Library/Application Support/UsageBar/usagebar.log`
  shows every refresh attempt and its outcome.

## Start over

```bash
pkill -x UsageBar
rm -rf ~/Library/Application\ Support/UsageBar   # settings + cached snapshot
open /Applications/UsageBar.app
```

That also removes the "launch at login" state? No — that is a separate file:
`~/Library/LaunchAgents/io.github.zhangqihenry.ai-usage-bar.plist`. Delete it (or
toggle the menu item off) to stop auto launch.
