#!/usr/bin/env bash
#
# Build Wisp from source and install it to /Applications.
#
# Because the app is built locally (never downloaded), it carries no quarantine
# flag — so it opens with NO Gatekeeper prompt. This is the cleanest way to run
# Wisp until notarized builds are available.
#
# Usage: Scripts/install.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"

"$ROOT/Scripts/build-app.sh" "$CONFIG"

echo "==> Quitting any running Wisp"
pkill -f "Wisp.app/Contents/MacOS/Wisp" 2>/dev/null || true
sleep 1

echo "==> Installing to /Applications/Wisp.app"
# Capture the outgoing app's designated requirement before deleting it — it's
# what decides below whether the existing Accessibility grant survives.
OLD_REQ="$(codesign -d -r- /Applications/Wisp.app 2>/dev/null || true)"
rm -rf /Applications/Wisp.app
cp -R "$ROOT/dist/Wisp.app" /Applications/Wisp.app

# macOS TCC keys the Accessibility grant to the app's designated requirement.
# Ad-hoc DRs embed the per-build binary hash (cdhash), so they change on every
# rebuild; identity DRs (Scripts/make-dev-cert.sh, or CI's Developer ID) pin
# the signing certificate, so they're stable across rebuilds and only change
# when the cert does. Whenever the DR changed, the previous grant is stale —
# System Settings still shows Wisp "enabled", but the grant no longer applies
# and paste silently re-prompts — so reset it for one clean re-prompt. Only a
# provably identical DR skips the reset (unreadable output fails toward the
# harmless reset). Two caveats on the skip: it preserves whatever decision
# exists, including an earlier Deny (if paste stays silent, run
# `tccutil reset Accessibility com.brinas.wisp` and paste again); and the
# outgoing app's DR stands in for the one TCC keyed the grant to, which holds
# as long as installs go through this script.
# Read the ID from the freshly-built bundle so this works on a first install too.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/dist/Wisp.app/Contents/Info.plist" 2>/dev/null || true)"
NEW_REQ="$(codesign -d -r- "$ROOT/dist/Wisp.app" 2>/dev/null || true)"
if [[ -z "$BUNDLE_ID" ]]; then
    echo "==> Skipping Accessibility reset (couldn't read bundle id)"
elif [[ -n "$NEW_REQ" && "$NEW_REQ" == "$OLD_REQ" ]]; then
    echo "==> Signing requirement unchanged — keeping the existing Accessibility decision"
else
    echo "==> Resetting stale Accessibility grant for $BUNDLE_ID"
    # NB: never pass an empty id — `tccutil reset Accessibility ""` would wipe
    # EVERY app's Accessibility grant, not just Wisp's. The -z guard above
    # ensures we only ever reset our own bundle. The reset is best-effort.
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

# Remove the staging copy so there's only ever one launchable Wisp.app (the one
# in /Applications). dist/ is just build output — keeping a second runnable copy
# around invites launching the wrong one and muddies which app a TCC grant maps to.
echo "==> Removing build staging copy ($ROOT/dist/Wisp.app)"
rm -rf "$ROOT/dist/Wisp.app"

open /Applications/Wisp.app
echo "✓ Installed and launched. Grant Accessibility when prompted (used only to paste with ⌘V)."
