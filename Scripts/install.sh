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

open /Applications/Wisp.app
echo "✓ Installed and launched. Grant Accessibility when prompted (used only to paste with ⌘V)."
