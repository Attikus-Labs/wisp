#!/usr/bin/env bash
#
# Build Wisp.app and (re)launch it. Handy during development.
#
# Usage:
#   Scripts/run.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"

"$ROOT/Scripts/build-app.sh" "$CONFIG"

echo "▸ Relaunching..."
killall Wisp 2>/dev/null || true
open "$ROOT/dist/Wisp.app"
echo "✓ Wisp is running — look for the clipboard icon in the menu bar (⌘⇧V to open)."
