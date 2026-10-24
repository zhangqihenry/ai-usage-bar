# Data sources

Both numbers come from the same places the vendors' own CLIs use. Neither
endpoint is documented or supported; treat every field as optional and every
response shape as able to change overnight.

## Codex / ChatGPT

| | |
|---|---|
| Endpoint | `GET https://chatgpt.com/backend-api/wham/usage` |
| Auth | `Authorization: Bearer <access token>` |
| Extra headers | `chatgpt-account-id: <account id>`, `User-Agent: codex_cli_rs/…`, `originator: codex_cli_rs` |
| Credentials | `$CODEX_HOME/auth.json`, else `~/.codex/auth.json` → `tokens.access_token`, `tokens.account_id` |
| Written by | Codex CLI, the Codex desktop app, the ChatGPT desktop app |

Response (trimmed):

```json
{
  "email": "you@example.com",
  "plan_type": "prolite",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 0,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 590415,
      "reset_at": 1793325915
    },
    "secondary_window": null
  },
  "credits": { "has_credits": false, "balance": "0" }
}
```

Notes:

- **`primary_window` is not always the 5 hour window.** Plans differ: a Pro Lite
  account answers with a single 7 day window in the primary slot and no secondary
  at all. Buckets are assigned by `limit_window_seconds` (18 000 s = 5 h,
  604 800 s = 1 week) with the API ordering as a fallback.
- `reset_at` is a unix timestamp; `reset_after_seconds` is a relative fallback
  used when `reset_at` is missing.
- `used_percent` can exceed 100; the parser clamps to 0…100.
- An `auth.json` holding only `OPENAI_API_KEY` cannot read subscription quota —
  that requires an OAuth session. The app says so instead of failing obscurely.
- 403 here is almost always network policy (region block / Cloudflare), not bad
  credentials. Bad credentials answer 401.

## Claude

| | |
|---|---|
| Endpoint | `GET https://api.anthropic.com/api/oauth/usage` |
| Auth | `Authorization: Bearer <Claude Code OAuth access token>` |
| Required header | `anthropic-beta: oauth-2025-04-20` |
| User-Agent | `claude-code/<version>` (anything else lands in a stricter rate-limit bucket) |
| Credentials | Keychain item `Claude Code-credentials`, else `~/.claude/.credentials.json`, else `$CLAUDE_CODE_OAUTH_TOKEN` |

Response (flat shape, older clients):

```json
{
  "five_hour": { "utilization": 63.0, "resets_at": "2026-10-23T18:00:00.000+00:00" },
  "seven_day": { "utilization": 13.0, "resets_at": "2026-10-27T00:59:59.951713+00:00" },
  "seven_day_opus": null,
  "seven_day_sonnet": { "utilization": 1.0, "resets_at": "2026-10-26T03:00:00.951719+00:00" }
}
```

Response (structured shape, current clients):

```json
{
  "limits": [
    { "kind": "session", "percent": 42.0, "resets_at": "…" },
    { "kind": "weekly_all", "percent": 18.0, "resets_at": "…" },
    { "kind": "weekly_scoped", "percent": 7.0, "resets_at": "…",
      "scope": { "model": { "display_name": "Opus" } } }
  ]
}
```

Notes:

- **`utilization` is a percentage (0–100), never a fraction.** A reported `1.0`
  means one percent used. Do not "helpfully" multiply by 100.
- Any bucket may be `null` on plans without that cap; every field is optional.
- The structured shape carries no window duration, so `kind` decides the bucket:
  `session` → 5 hour, anything containing `weekly` → week. Scoped entries become
  extra rows (`Opus`, `Sonnet`, and whatever the vendor add next).
- The endpoint rate limits hard on the order of a handful of calls per window.
  `UsageService` enforces a 240 s floor per token regardless of the user's
  setting, and the whole response is cached in `snapshot.json`.
- `resets_at` timestamps arrive with microseconds and a numeric offset
  (`…59.951713+00:00`), which the parser handles.

## Token lifetime

| | |
|---|---|
| Codex access token | ~10 days, refreshed by the vendor client |
| Claude access token | ~1 hour, refreshed by Claude Code while it runs |

The app only reads these tokens. It never writes to the vendor's auth file or
Keychain and never performs a refresh grant: refresh tokens rotate, and burning
one behind the vendor CLI's back can sign the user out of their own tool. When a
token is expired the UI says "session expired, reopen the client", which is the
action that fixes it.

## Region blocking

`chatgpt.com` refuses connections from mainland China, Hong Kong and a few other
networks with an HTML 403 page ("Unable to load site … If you are using a VPN,
try turning it off"). The app maps that to a "blocked" error and points at the
proxy settings. `api.anthropic.com` is generally reachable, but the same proxy
setting applies to both.

## Mapping the numbers to the menu bar

| Vendor field | Bucket | Menu bar position |
|---|---|---|
| Codex `primary_window`/`secondary_window` with `limit_window_seconds = 18000` | 5 h | first number |
| … `limit_window_seconds = 604800` | week | second number |
| Claude `five_hour` / `limits[kind=session]` | 5 h | first number |
| Claude `seven_day` / `limits[kind=weekly_all]` | week | second number |
| Claude `limits[kind=weekly_scoped]` | week, scoped | extra row in the menu |
