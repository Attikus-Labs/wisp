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

# Sign with the Hardened Runtime. Identity, in priority order:
#   1. SIGN_IDENTITY env — CI passes a Developer ID Application certificate;
#      explicitly EMPTY means "ad-hoc, please" (the pre-dev-cert behavior —
#      never silently substitute a personal cert for an empty CI secret);
#   2. the local "Wisp Local Dev" certificate (Scripts/make-dev-cert.sh) —
#      stable across rebuilds, so the TCC Accessibility grant sticks;
#   3. ad-hoc — runs fine, but the signature is pinned to this build's hash,
#      so the Accessibility grant goes stale on every reinstall.
DEV_CERT="Wisp Local Dev"
if [[ -n "${SIGN_IDENTITY+set}" ]]; then
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$DEV_CERT"; then
    SIGN_IDENTITY="$DEV_CERT"
else
    SIGN_IDENTITY="-"
    echo "⚠ Ad-hoc signing: the Accessibility grant goes stale on every reinstall"
    echo "  (install.sh resets it for a clean re-prompt). Run Scripts/make-dev-cert.sh"
    echo "  once to mint a stable identity that keeps the grant across rebuilds."
fi
echo "▸ Signing (identity: $SIGN_IDENTITY)..."
if ! codesign --force --options runtime \
    --entitlements "$ROOT/Resources/Wisp.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$APP"; then
    echo "✗ Signing failed." >&2
    if [[ "$SIGN_IDENTITY" == "$DEV_CERT" ]]; then
        echo "  The dev cert needs the login keychain unlocked — over SSH/headless," >&2
        echo "  run: security unlock-keychain ~/Library/Keychains/login.keychain-db" >&2
        echo "  Or build ad-hoc with SIGN_IDENTITY=- (the Accessibility grant then" >&2
        echo "  goes stale on the next install)." >&2
    fi
    exit 1
fi

codesign --verify --verbose=2 "$APP"
echo "✓ Built $APP"
