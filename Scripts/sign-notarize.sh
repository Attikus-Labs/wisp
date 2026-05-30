#!/usr/bin/env bash
#
# Re-sign dist/Wisp.app with a Developer ID, notarize it with Apple, and staple
# the ticket. Run AFTER Scripts/build-app.sh.
#
# Required environment:
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#
# Notarization credentials — provide EITHER a stored notarytool profile:
#   NOTARY_PROFILE  name of a `notarytool store-credentials` keychain profile
# OR an App Store Connect API key:
#   AC_API_KEY_P8_PATH   path to the AuthKey_XXXX.p8 file
#   AC_API_KEY_ID        the key id
#   AC_API_ISSUER_ID     the issuer id
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Wisp.app"
ZIP="$ROOT/dist/Wisp.zip"

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity}"

echo "==> Re-signing with Developer ID ($SIGN_IDENTITY)"
codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Resources/Wisp.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Zipping for notarization"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notary service (this waits for the result)"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
else
    : "${AC_API_KEY_P8_PATH:?Set NOTARY_PROFILE or the AC_API_* variables}"
    : "${AC_API_KEY_ID:?}"
    : "${AC_API_ISSUER_ID:?}"
    xcrun notarytool submit "$ZIP" \
        --key "$AC_API_KEY_P8_PATH" \
        --key-id "$AC_API_KEY_ID" \
        --issuer "$AC_API_ISSUER_ID" \
        --wait
fi

echo "==> Stapling ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Refresh the zip so the distributed archive contains the stapled ticket.
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Done: notarized + stapled $APP"
