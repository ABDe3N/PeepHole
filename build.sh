#!/bin/bash
# Builds NetHog.app into ./build. Pass "install" to also copy it to /Applications.
#   UNIVERSAL=1      build for both Apple silicon and Intel
#   SIGN_IDENTITY=…  sign with a Developer ID (hardened runtime) instead of ad-hoc
set -euo pipefail
cd "$(dirname "$0")"

# --disable-keychain: dependencies are public, so never prompt for GitHub credentials.
SWIFT_FLAGS=(-c release --disable-keychain)
if [ "${UNIVERSAL:-0}" = "1" ]; then
    SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${SWIFT_FLAGS[@]}"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

APP="build/NetHog.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/NetHog" "$APP/Contents/MacOS/NetHog"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# ditto keeps the framework's internal symlinks intact.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --sign - "$APP" >/dev/null
else
    # Sign inside-out, as Sparkle's docs require for non-sandboxed apps.
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
    sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
    sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
    sign "$SPARKLE/Versions/B/Autoupdate"
    sign "$SPARKLE/Versions/B/Updater.app"
    sign "$SPARKLE"
    sign "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/NetHog"))"

if [ "${1:-}" = "install" ]; then
    osascript -e 'quit app "NetHog"' 2>/dev/null || true
    rm -rf /Applications/NetHog.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/NetHog.app"
    open /Applications/NetHog.app
fi
