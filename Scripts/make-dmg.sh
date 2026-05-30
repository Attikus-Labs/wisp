#!/usr/bin/env bash
#
# Build a distributable compressed .dmg from dist/Wisp.app, with the customary
# drag-to-Applications layout. Run AFTER build-app.sh (and sign-notarize.sh for
# release builds).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Wisp.app"

if [[ ! -d "$APP" ]]; then
    echo "Wisp.app not found — run Scripts/build-app.sh first." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/dist/Wisp-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/Wisp.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "Wisp" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"

echo "==> Created $DMG"
