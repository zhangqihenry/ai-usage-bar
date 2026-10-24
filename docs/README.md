# Documentation

Design notes and operational guides. The code comments explain *what* a line
does; these files explain *why* the project is shaped this way and how to work on
it without rediscovering the same traps.

| File | Read it when |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | You are changing the data flow, adding a provider, or wondering where state lives. |
| [DATA-SOURCES.md](DATA-SOURCES.md) | A number looks wrong, a request fails, or a vendor changed something. Every endpoint, header and credential path is listed here. |
| [DEVELOPMENT.md](DEVELOPMENT.md) | You are setting up the toolchain, running tests, debugging the menu bar, or cutting a release. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | The app runs but the menu bar item is invisible, or a refresh keeps failing. |

The repository root [README.md](../README.md) is the user facing document: what
the app does, how to install it, what the numbers mean.

Each source folder also has a short `README.md` that lists its files one by one.
Start there if you only need to find a specific file.
