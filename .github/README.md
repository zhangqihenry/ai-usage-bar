# .github

| Path | Purpose |
|---|---|
| `workflows/ci.yml` | Builds the package, runs the self test suite, assembles the app bundle on a macOS runner. Runs on push to `main`, on pull requests, and manually. |
| `ISSUE_TEMPLATE/bug_report.md` | Bug report form that asks for the one thing that makes quota bugs diagnosable: `UsageBar --print` output. |

Keep CI on `macos-14` or newer: the package targets macOS 13 and uses Swift 5.9
features. The workflow deliberately does not need Xcode — it checks that the
Command Line Tools path still works.
