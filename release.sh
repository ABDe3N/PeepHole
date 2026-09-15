#!/bin/bash
# Builds a universal NetHog.app and packages it as build/NetHog-<version>.dmg.
#
# Without credentials it makes an ad-hoc signed DMG (fine for testing; other Macs
# will block it). For a public release that opens without Gatekeeper warnings:
#
#   1. Join the Apple Developer Program and create a "Developer ID Application"
#      certificate (Xcode > Settings > Accounts > Manage Certificates).
#   2. Store notarization credentials once (use an app-specific password):
#        xcrun notarytool store-credentials nethog-notary \
#          --apple-id you@example.com --team-id TEAMID1234
#   3. Run:
#        SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" \
#        NOTARY_PROFILE=nethog-notary ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${SIGN_IDENTITY:--}"
PROFILE="${NOTARY_PROFILE:-}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP="build/NetHog.app"
DMG="build/NetHog-$VERSION.dmg"

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait
}

UNIVERSAL=1 SIGN_IDENTITY="$IDENTITY" ./build.sh

if [ "$IDENTITY" != "-" ] && [ -n "$PROFILE" ]; then
    # Notarize and staple the app itself so it also opens offline once copied out of the DMG.
    ZIP="build/NetHog-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    rm -f "$ZIP"
    xcrun stapler staple "$APP"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "NetHog $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [ "$IDENTITY" = "-" ]; then
    echo "Built $DMG (ad-hoc signed: other Macs will block it; see top of release.sh)"
    exit 0
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
if [ -z "$PROFILE" ]; then
    echo "Built $DMG (signed, NOT notarized: set NOTARY_PROFILE to notarize)"
    exit 0
fi
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
shasum -a 256 "$DMG"
echo "Built $DMG (signed, notarized, stapled)"
