# Fixtures

Recorded API responses, anonymised. They are loaded with
`Bundle.module.url(forResource:withExtension:subdirectory:"Fixtures")` and copied
verbatim by SwiftPM (`resources: [.copy("Fixtures")]` in `Package.swift`).

| File | Shape | What it pins down |
|---|---|---|
| `codex_single_window.json` | Codex, `primary_window` only, `limit_window_seconds = 604800` | A weekly-only plan must land in `weekly`, with no 5 h bucket. |
| `codex_two_windows.json` | Codex, both windows, `used_percent = 112` on the week | Bucket classification by length, clamping to 100, `reset_at` winning over `reset_after_seconds`, `limit_reached`, credits note. |
| `claude_flat.json` | Claude, `five_hour` / `seven_day` / `seven_day_sonnet` | The older flat shape, `utilization: 1.0` staying one percent, model scoped bucket. |
| `claude_limits.json` | Claude, `limits[]` with `session`, `weekly_all`, `weekly_scoped` | The newer structured shape and `scope.model.display_name`. |

Rules:

- Never put a real token, e-mail or account id in a fixture. Use `user-test`,
  `test@example.com`, `083af435-0000-…`.
- Keep the fields the parser ignores too (credits, extra_usage). They are what
  makes a "why did this break" investigation cheap.
- If you add a fixture, add the suite case that uses it in the same commit.
