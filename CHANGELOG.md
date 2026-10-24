# Changelog

All notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[semantic versioning](https://semver.org/).

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
