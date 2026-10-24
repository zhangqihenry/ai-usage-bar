#!/bin/bash
#
# Installs the app into /Applications (or ~/Applications without admin rights)
# and starts it.
#
# Usage:
#   scripts/install.sh            # build, install, launch
#   scripts/install.sh --login    # also start at login

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="UsageBar"
APP_SOURCE="$ROOT/dist/$APP_NAME.app"
WANT_LOGIN=0

for arg in "$@"; do
    case "$arg" in
        --login) WANT_LOGIN=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 64 ;;
    esac
done

"$ROOT/scripts/build-app.sh"

# /Applications first; fall back to the per-user folder when it is not writable.
if [ -w /Applications ]; then
    DEST="/Applications/$APP_NAME.app"
else
    mkdir -p "$HOME/Applications"
    DEST="$HOME/Applications/$APP_NAME.app"
fi

echo "==> Installing to $DEST"
# Quit a running copy so the new binary replaces cleanly.
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R "$APP_SOURCE" "$DEST"

echo "==> Launching"
open "$DEST"

if [ "$WANT_LOGIN" = "1" ]; then
    echo "==> Enabling launch at login"
    # The app owns the LaunchAgent; the simplest trigger is the menu item.
    osascript >/dev/null 2>&1 <<APPLESCRIPT || echo "    (enable it from the menu: Launch at Login)"
tell application "System Events" to tell process "$APP_NAME" to click menu bar item 1 of menu bar 2
APPLESCRIPT
fi

echo "==> Installed. Look for the Cx / Cl numbers in the menu bar."
