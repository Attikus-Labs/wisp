#!/usr/bin/env bash
#
# Cut a Wisp release: build the .app, package a .dmg, and publish a GitHub
# Release with checksums.
#
# Notarization is AUTOMATIC when signing credentials are present in the
# environment (SIGN_IDENTITY + notary creds — see docs/RELEASING.md). Without
# them it produces an UNSIGNED build, and the release notes tell downloaders to
# right-click -> Open past Gatekeeper. So the same command improves itself the
# day you add a Developer ID — no edits required.
#
# Usage:
#   Scripts/release.sh [version]     # defaults to CFBundleShortVersionString in Info.plist
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLIST="$ROOT/Resources/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")}"
TAG="v$VERSION"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

echo "==> Releasing $REPO $TAG"

# 1. Build the .app (ad-hoc by default; Developer ID if SIGN_IDENTITY is set).
"$ROOT/Scripts/build-app.sh" release

# 2. Notarize when credentials are available; otherwise this is an unsigned build.
SIGNED=false
if [[ -n "${SIGN_IDENTITY:-}" && ( -n "${NOTARY_PROFILE:-}" || -n "${AC_API_KEY_P8_PATH:-}" ) ]]; then
    echo "==> Signing credentials detected — notarizing"
    "$ROOT/Scripts/sign-notarize.sh"
    SIGNED=true
else
    echo "==> No signing credentials — producing an UNSIGNED build"
fi

# 3. Package the dmg and checksum it.
"$ROOT/Scripts/make-dmg.sh"
DMG="$ROOT/dist/Wisp-$VERSION.dmg"
SUMS="$ROOT/dist/SHA256SUMS-$VERSION.txt"
( cd "$ROOT/dist" && shasum -a 256 "Wisp-$VERSION.dmg" | tee "SHA256SUMS-$VERSION.txt" )

# 4. Compose release notes (quoted heredoc keeps backticks literal; we swap the
#    version placeholder afterwards).
NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT
if $SIGNED; then
    read -r -d '' NOTES <<'EOF' || true
Wisp __VERSION__ — signed & notarized.

**Install:** download `Wisp-__VERSION__.dmg`, open it, drag **Wisp** to Applications.
Or: `brew install --cask Attikus-Labs/tap/wisp`

**Verify:** `shasum -a 256 -c SHA256SUMS-__VERSION__.txt`
EOF
else
    read -r -d '' NOTES <<'EOF' || true
Wisp __VERSION__ — **unsigned build** (no Apple Developer ID yet).

Because this build isn't signed/notarized by Apple, Gatekeeper will block it on
first launch. It's safe — the source is right here and CI builds it — you just
have to approve it once.

**Install**
1. Download `Wisp-__VERSION__.dmg`, open it, and drag **Wisp** to Applications.
2. Launch it the first time with **right-click (or Control-click) Wisp.app → Open → Open**.
   (Double-clicking will only show a "can't be opened" / "unidentified developer" dialog.)
   If macOS still refuses, run once: `xattr -dr com.apple.quarantine /Applications/Wisp.app`
3. Grant **Accessibility** when prompted — it's used only to paste with ⌘V.

**Verify the download:** `shasum -a 256 -c SHA256SUMS-__VERSION__.txt`

A future release will be signed & notarized for a clean one-click install.
EOF
fi
NOTES="${NOTES//__VERSION__/$VERSION}"
printf '%s\n' "$NOTES" > "$NOTES_FILE"

# 5. Create or update the GitHub Release.
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "==> Updating existing release $TAG"
    gh release edit "$TAG" --title "Wisp $VERSION" --notes-file "$NOTES_FILE"
    gh release upload "$TAG" "$DMG" "$SUMS" --clobber
else
    echo "==> Creating release $TAG"
    gh release create "$TAG" "$DMG" "$SUMS" \
        --target main \
        --title "Wisp $VERSION" \
        --notes-file "$NOTES_FILE"
fi

echo "==> Done: $(gh release view "$TAG" --json url -q .url)"
