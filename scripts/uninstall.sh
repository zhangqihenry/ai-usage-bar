#!/bin/bash
#
# Removes UsageBar from the machine:
#   1. unloads and deletes the LaunchAgent,
#   2. quits the running app,
#   3. deletes the .app bundle.
#
# User data (~/Library/Application Support/UsageBar) is kept unless --purge is
# passed, because it contains no secrets but does contain the user's settings.
#
# Usage:
#   scripts/uninstall.sh           # keep settings
#   scripts/uninstall.sh --purge   # also delete settings and cached snapshot

set -euo pipefail

APP_NAME="UsageBar"
LABEL="io.github.zhangqihenry.ai-usage-bar"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT="$HOME/Library/Application Support/UsageBar"
PURGE=0

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 64 ;;
    esac
done

echo "==> Stopping the LaunchAgent"
if [ -f "$AGENT" ]; then
    launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
    rm -f "$AGENT"
fi

echo "==> Quitting the app"
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Removing the app bundle"
for candidate in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
    if [ -d "$candidate" ]; then
        rm -rf "$candidate"
        echo "    removed $candidate"
    fi
done

if [ "$PURGE" = "1" ]; then
    echo "==> Removing user data"
    rm -rf "$SUPPORT"
else
    echo "==> Keeping $SUPPORT (use --purge to delete it)"
fi

echo "==> Done."
