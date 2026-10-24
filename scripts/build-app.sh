#!/bin/bash
#
# Builds dist/UsageBar.app from the SwiftPM executable.
#
# Why assemble the bundle by hand instead of using Xcode? The project must be
# buildable with Command Line Tools only, and a menu bar app needs exactly:
# a binary, an Info.plist and (optionally) an icon. That is cheaper to maintain
# than an .xcodeproj, and reviewers can diff every step.
#
# Usage:
#   scripts/build-app.sh              # release build
#   CONFIG=debug scripts/build-app.sh # debug build
#
# Environment:
#   CONFIG  SwiftPM configuration, default "release"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="UsageBar"
BUNDLE_ID="io.github.zhangqihenry.ai-usage-bar"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
CONFIG="${CONFIG:-release}"

echo "==> Building usagebar ($CONFIG)"
swift build -c "$CONFIG" --product usagebar
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/usagebar"

APP="$ROOT/dist/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/$APP_NAME"
chmod +x "$CONTENTS/MacOS/$APP_NAME"

# Icon: committed as .icns so a normal build has no extra dependency. Regenerate
# with `make icon` after changing scripts/make-icon.swift.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

# LSUIElement=1 keeps the app out of the Dock and the app switcher; it is a menu
# bar agent, not a window app.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>UsageBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT licensed</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough for the app to run locally (Apple silicon refuses
# unsigned code); it is not a distribution signature. The Keychain is read via
# /usr/bin/security, so this signature plays no part in Keychain access.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null

echo "==> Done: $APP ($VERSION build $BUILD_NUMBER)"
echo "    Run it with: open \"$APP\""
