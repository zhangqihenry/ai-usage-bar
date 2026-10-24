# Getting credentials

The app does not have its own login. It reads the OAuth session that OpenAI's and
Anthropic's own tools already keep on disk, and those sessions are the only way to
see quota: neither vendor offers a standalone "give me my usage" API key.

So "I installed ChatGPT and Claude" is not enough. Each service needs **one
sign-in with its developer tool**:

| Service | One-time setup | What it leaves behind |
|---|---|---|
| Codex | Codex CLI `codex login`, or the Codex desktop app | `~/.codex/auth.json` (`auth_mode: "chatgpt"`) |
| Claude | Claude Code, signed in once | Keychain `Claude Code-credentials` (or `~/.claude/.credentials.json`) |

The plain **ChatGPT desktop app does not create `~/.codex/auth.json`**, and the
plain **Claude desktop app does not create the Claude Code credential**. Measured,
not assumed: the ChatGPT.app binary contains no reference to `.codex` at all.
Those apps keep their own web session, which the quota endpoints do not accept.

## Codex

```bash
npm install -g @openai/codex
codex login          # opens the browser, sign in with the same ChatGPT account
```

Then check:

```bash
ls -l ~/.codex/auth.json
# {"auth_mode":"chatgpt", "tokens": {...}, "last_refresh": "..."}
```

Notes:

- Any ChatGPT plan works; the app shows whatever the account has (Pro Lite, Plus,
  Pro). A plan without a 5 hour cap simply shows a dash for that column.
- An `auth.json` containing only `OPENAI_API_KEY` is not usable: subscription
  quota needs the OAuth session, not an API key.
- Set `CODEX_HOME` if your Codex install keeps its state somewhere else; the app
  honours it.

## Claude

```bash
npm install -g @anthropic-ai/claude-code
claude               # sign in once with the Claude account that has Pro/Max
```

Then check:

```bash
security find-generic-password -s "Claude Code-credentials" >/dev/null && echo ok
```

Notes:

- The app needs a Claude **subscription** session; an Anthropic API key has no
  quota windows to report.
- The app reads the Keychain item through `/usr/bin/security`, the same tool
  Claude Code writes it with, so there is usually no prompt. If macOS does ask,
  choose "Always Allow"; the grant belongs to `security`, so rebuilding the app
  does not bring the prompt back. An unanswered prompt times out after 30 s and
  the menu says so.
- The access token in that item lasts a few hours and only the `claude` CLI
  renews it. If you use Claude Code solely through the Claude desktop app, the
  item is never renewed and the menu shows "session expired"; run `claude` in a
  terminal to renew it.
- `CLAUDE_CODE_OAUTH_TOKEN` in the environment overrides everything. Useful in CI,
  but those tokens expire in about an hour.

## Machines without the CLIs, or a shared machine

- Both CLIs are Node packages and run anywhere Node does; installing one to sign
  in is usually less work than any workaround.
- Copying `~/.codex/auth.json` between machines works and is what Codex itself
  does on login, but the file contains a refresh token: treat it like a password,
  never commit it, and do not put it in a shared folder.
- `CLAUDE_CODE_OAUTH_TOKEN` can be exported per session instead of using the
  Keychain, at the cost of doing it again every hour.
- There is no way to read quota from a ChatGPT or Claude web session cookie. Both
  endpoints reject it.

## Why there is no "Sign in" button in the app

The quota endpoints are undocumented vendor-internal APIs tied to the OAuth
clients of Codex and Claude Code. An app that implements its own OAuth grant would
have to impersonate those clients:

- **Codex** uses a public PKCE client, so a third-party login is technically
  possible, but the flow, scopes and client id can change without notice, and the
  account sees a login it did not start from OpenAI's own tool.
- **Claude** is worse: Anthropic's terms restrict using Claude Code OAuth
  credentials in other products. Building that into a distributed app puts every
  user in a grey zone.

Reading a session the user already created with the vendor's own CLI stays on the
safe side of that line, and it is what this app does. If a vendor ships a public
usage API, this page goes away and the app gets a real login.
