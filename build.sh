#!/bin/bash
# Builds NetHog.app into ./build. Pass "install" to also copy it to /Applications.
#   UNIVERSAL=1      build for both Apple silicon and Intel
#   SIGN_IDENTITY=…  sign with a Developer ID (hardened runtime) instead of ad-hoc
set -euo pipefail
cd "$(dirname "$0")"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/NetHog"

APP="build/NetHog.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NetHog"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP" >/dev/null
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/NetHog"))"

if [ "${1:-}" = "install" ]; then
    osascript -e 'quit app "NetHog"' 2>/dev/null || true
    rm -rf /Applications/NetHog.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/NetHog.app"
    open /Applications/NetHog.app
fi
