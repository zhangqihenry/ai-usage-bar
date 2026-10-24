# Changelog

All notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Settings edits no longer trigger a forced refresh on every keystroke. Display
  options just re-render; a proxy change or a re-enabled service refreshes once,
  debounced. This was the main way to run into Claude's 429.
- Numbers kept from an earlier success are no longer presented as current: the
  "updated" time used to move on every failed attempt, so the stale warning never
  appeared. Kept numbers are now dimmed, labelled "showing data from … ago", and
  the footer says "Last checked … (some data is stale)".
- Reset times from Claude's structured `limits` response were dropped
  (`resets_at` was read as `resetsAt`).
- Adding a setting in a future release no longer resets every preference; each
  key now falls back to its own default, and a bad value costs only that field.
- Launch at Login no longer starts a second copy when switched on, and no longer
  quits the app when switched off after a login launch. The agent is re-pointed
  when the app bundle moves, and only one copy of the app runs per session.
- A Keychain access prompt left unanswered no longer blocks every later refresh;
  the read times out after 30 s with an explanation.
- `scripts/install.sh --login` now actually enables launch at login.
- Codex windows without `used_percent` are no longer shown as 0%.
- When both windows land in the same bucket, the moved one is relabelled to
  match its slot.

### Changed

- After an HTTP 429 a service pauses for 5 minutes, doubling up to an hour, and
  even "Refresh Now" respects it. Network errors (no request reached the vendor)
  no longer count against the per-service minimum interval and are retried after
  30 s, 60 s, 120 s … up to the polling interval. Wake refreshes wait 5 s.
- One HTTP session is reused across refreshes and released when the proxy
  changes, instead of leaking a new session per refresh.
- `--print` / `--json` no longer read or write `snapshot.json`.
- The dropdown and tooltip follow "show remaining", like the title already did.

### Added

- Opt-in threshold notifications, and amber/red threshold steppers in Settings.
- Claude extra usage row when the account has it switched on.
- Vendor notes ("limit reached", Codex credits) in the dropdown.
- `--enable-launch-at-login` / `--disable-launch-at-login` CLI flags.
- Release workflow: pushing a `v*` tag that matches `VERSION` publishes a zipped
  app with its SHA-256.
- Tests for refresh pacing, settings compatibility, credential parsing,
  staleness, alerts and extra usage (76 → 122 checks).

## [0.1.0] — 2026-10-23

First working release.

### Added

- Menu bar item showing ChatGPT (Codex) and Claude quota: 5 hour window and
  weekly window, percent used, coloured by threshold, `!` marker on failed
  refresh.
- Dropdown with per-window progress bars, reset countdowns, plan name, model
  scoped weekly buckets, and plain language error messages.
- Codex provider using `chatgpt.com/backend-api/wham/usage`, with bucket
  classification by window length so weekly-only plans display correctly.
- Claude provider using `api.anthropic.com/api/oauth/usage`, supporting both the
  flat bucket shape and the structured `limits` array.
- Settings window: refresh interval, window selection, used/remaining, per
  service toggles, proxy mode (system / direct / manual HTTP or SOCKS5), reset.
- Launch at login through a user LaunchAgent.
- Headless CLI: `--print`, `--json`, `--version`, `--help`, meaningful exit codes.
- Optional file logging with `USAGEBAR_DEBUG=1`.
- Self test executable with JSON fixtures; no Xcode required to build or test.
