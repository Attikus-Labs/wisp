#!/usr/bin/env bash
#
# Assemble Wisp.app from the SwiftPM-built executable.
#
# Usage:
#   Scripts/build-app.sh [debug|release]
#
# Produces dist/Wisp.app, ad-hoc signed with the Hardened Runtime so it runs
# locally. CI re-signs with a real Developer ID before notarizing (see
# Scripts/sign-notarize.sh).
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Wisp"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "▸ Building ($CONFIG)..."
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN" ]]; then
    echo "✗ Executable not found at $BIN" >&2
    exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
echo "▸ Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Optional icon (drop an AppIcon.icns in Resources/ to brand the bundle).
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
        "$APP/Contents/Info.plist" 2>/dev/null || true
fi

# Menu bar template glyph (the stacked-clips mark). Bundled so AppDelegate can
# load it as a tintable template; harmless to omit (it falls back to a symbol).
if [[ -f "$ROOT/Resources/MenuBarIcon.pdf" ]]; then
    cp "$ROOT/Resources/MenuBarIcon.pdf" "$APP/Contents/Resources/MenuBarIcon.pdf"
fi

# Ad-hoc sign with the Hardened Runtime. CI overrides SIGN_IDENTITY with a
# Developer ID Application certificate for distributable builds.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "▸ Signing (identity: $SIGN_IDENTITY)..."
codesign --force --options runtime \
    --entitlements "$ROOT/Resources/Wisp.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$APP"

codesign --verify --verbose=2 "$APP"
echo "✓ Built $APP"
