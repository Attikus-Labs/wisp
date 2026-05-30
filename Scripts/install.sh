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
rm -rf /Applications/Wisp.app
cp -R "$ROOT/dist/Wisp.app" /Applications/Wisp.app

# Ad-hoc builds (no Developer ID) get a fresh code-directory hash on every
# rebuild, and macOS TCC keys ad-hoc apps by that hash. So a previous
# Accessibility grant goes stale on each reinstall — System Settings still shows
# Wisp "enabled", but the grant no longer applies to the new binary and paste
# silently re-prompts. Reset the stale grant so you get one clean re-prompt.
# (A stable Developer ID, or a self-signed dev cert, would make the grant stick.)
# Read the ID from the freshly-built bundle so this works on a first install too.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/dist/Wisp.app/Contents/Info.plist" 2>/dev/null || true)"
if [[ -n "$BUNDLE_ID" ]]; then
    echo "==> Resetting stale Accessibility grant for $BUNDLE_ID"
    # NB: never pass an empty id — `tccutil reset Accessibility ""` would wipe
    # EVERY app's Accessibility grant, not just Wisp's. The -n guard above
    # ensures we only ever reset our own bundle. The reset is best-effort.
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
else
    echo "==> Skipping Accessibility reset (couldn't read bundle id)"
fi

# Remove the staging copy so there's only ever one launchable Wisp.app (the one
# in /Applications). dist/ is just build output — keeping a second runnable copy
# around invites launching the wrong one and muddies which app a TCC grant maps to.
echo "==> Removing build staging copy ($ROOT/dist/Wisp.app)"
rm -rf "$ROOT/dist/Wisp.app"

open /Applications/Wisp.app
echo "✓ Installed and launched. Grant Accessibility when prompted (used only to paste with ⌘V)."
