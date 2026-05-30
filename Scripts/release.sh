#!/usr/bin/env bash
#
# Publish a Wisp release.
#
# DEFAULT (no signing credentials): a SOURCE-ONLY release — verify the tag
# compiles, then create/update a GitHub Release whose notes point at
# `Scripts/install.sh`. GitHub auto-attaches the "Source code" archives; we ship
# no unsigned binary, because telling users to bypass Gatekeeper is the wrong
# tradeoff for a clipboard tool.
#
# WHEN SIGNING CREDS ARE PRESENT (SIGN_IDENTITY + notary creds — see
# docs/RELEASING.md): build, notarize, and attach a .dmg + checksums instead.
# Same command, so "add binaries later" needs no edits here.
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

HAVE_SIGNING=false
if [[ -n "${SIGN_IDENTITY:-}" && ( -n "${NOTARY_PROFILE:-}" || -n "${AC_API_KEY_P8_PATH:-}" ) ]]; then
    HAVE_SIGNING=true
fi

NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT

echo "==> Releasing $REPO $TAG"

if $HAVE_SIGNING; then
    echo "==> Signing credentials present — building a notarized binary release"
    "$ROOT/Scripts/build-app.sh" release
    "$ROOT/Scripts/sign-notarize.sh"
    "$ROOT/Scripts/make-dmg.sh"
    DMG="$ROOT/dist/Wisp-$VERSION.dmg"
    SUMS="$ROOT/dist/SHA256SUMS-$VERSION.txt"
    ( cd "$ROOT/dist" && shasum -a 256 "Wisp-$VERSION.dmg" | tee "SHA256SUMS-$VERSION.txt" )

    read -r -d '' NOTES <<'EOF' || true
Wisp __VERSION__ — signed & notarized.

**Install:** download `Wisp-__VERSION__.dmg`, open it, drag **Wisp** to Applications.
Or: `brew install --cask Attikus-Labs/tap/wisp`

**Verify:** `shasum -a 256 -c SHA256SUMS-__VERSION__.txt`
EOF
    NOTES="${NOTES//__VERSION__/$VERSION}"
    printf '%s\n' "$NOTES" > "$NOTES_FILE"

    if gh release view "$TAG" >/dev/null 2>&1; then
        gh release edit "$TAG" --title "Wisp $VERSION" --notes-file "$NOTES_FILE" --prerelease=false
        gh release upload "$TAG" "$DMG" "$SUMS" --clobber
    else
        gh release create "$TAG" "$DMG" "$SUMS" \
            --target main --title "Wisp $VERSION" --notes-file "$NOTES_FILE"
    fi
else
    echo "==> No signing credentials — publishing a SOURCE-ONLY release (no binary)"
    # Gate: make sure the tagged code actually builds before we publish it.
    swift build -c release >/dev/null

    read -r -d '' NOTES <<'EOF' || true
Wisp __VERSION__ — source release.

No prebuilt binary yet. Until Wisp is signed & notarized by Apple, the
responsible way to run a clipboard manager is to **build it from source** — so
the app you run is the code you can read right here.

**Install** (macOS 13+, Apple Command Line Tools — `xcode-select --install`):

```
git clone https://github.com/Attikus-Labs/wisp
cd wisp && git checkout __TAG__
Scripts/install.sh
```

Built locally, so macOS doesn't quarantine it — no Gatekeeper prompts.

The integrity anchor for this release is the immutable git tag `__TAG__`. A
signed, notarized `.dmg` (and a Homebrew cask) will arrive once the project has
an Apple Developer ID.
EOF
    NOTES="${NOTES//__VERSION__/$VERSION}"
    NOTES="${NOTES//__TAG__/$TAG}"
    printf '%s\n' "$NOTES" > "$NOTES_FILE"

    if gh release view "$TAG" >/dev/null 2>&1; then
        echo "==> Updating existing release $TAG (keeping it source-only)"
        gh release edit "$TAG" --title "Wisp $VERSION" --notes-file "$NOTES_FILE"
        # Drop any binaries from a prior run so the release stays source-only.
        gh release view "$TAG" --json assets -q '.assets[].name' | while read -r asset; do
            [[ -n "$asset" ]] && gh release delete-asset "$TAG" "$asset" -y || true
        done
    else
        gh release create "$TAG" --target main --title "Wisp $VERSION" --notes-file "$NOTES_FILE"
    fi
fi

echo "==> Done: $(gh release view "$TAG" --json url -q .url)"
