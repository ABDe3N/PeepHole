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
#   3. Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist.
#      Sparkle only offers an update when CFBundleVersion goes up.
#   4. Run:
#        SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID1234)" \
#        NOTARY_PROFILE=nethog-notary ./release.sh
#   5. Publish the DMG and appcast.xml together as a GitHub release (printed at the end).
#
# Updates are signed with the Sparkle key in your login keychain (account "NetHog").
# Back it up: .build/artifacts/sparkle/Sparkle/bin/generate_keys --account NetHog -x sparkle-key.txt
set -euo pipefail
cd "$(dirname "$0")"

REPO="ABDe3N/NetHog"
IDENTITY="${SIGN_IDENTITY:--}"
PROFILE="${NOTARY_PROFILE:-}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP="build/NetHog.app"
DMG="build/NetHog-$VERSION.dmg"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

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

# Sparkle feed listing just this release; installed copies read it from the latest GitHub release.
FEED_DIR="build/appcast"
rm -rf "$FEED_DIR"
mkdir -p "$FEED_DIR"
cp "$DMG" "$FEED_DIR/"
"$SPARKLE_BIN/generate_appcast" --account NetHog \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" "$FEED_DIR"

shasum -a 256 "$DMG"
echo "Built $DMG (signed, notarized, stapled) and $FEED_DIR/appcast.xml"
echo "Publish with: gh release create v$VERSION $DMG $FEED_DIR/appcast.xml --title \"NetHog $VERSION\""
