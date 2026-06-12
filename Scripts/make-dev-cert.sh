#!/usr/bin/env bash
#
# One-time setup: mint a self-signed "Wisp Local Dev" code-signing certificate
# in your login keychain, so locally-built Wisp keeps a *stable* signing
# identity across rebuilds.
#
# Why this exists: ad-hoc signatures (build-app.sh's fallback) pin the app's
# designated requirement to the exact binary hash (cdhash). macOS TCC stores
# the Accessibility grant against that requirement, so every rebuild silently
# invalidates the grant — System Settings still shows Wisp enabled, but ⏎
# paste re-prompts. An identity-signed build pins to the certificate instead,
# which is stable across rebuilds: grant Accessibility once and it sticks.
#
# macOS will ask for your login password twice: once now (recording the
# trust settings — Apple deliberately makes that non-automatable), and once
# on the first build that signs with the key (click "Always Allow" there so
# future builds sign silently). The private key is generated locally, stored
# only in your login keychain, and never leaves this machine.
#
# Usage: Scripts/make-dev-cert.sh
set -euo pipefail

NAME="Wisp Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$NAME"; then
    echo "✓ '$NAME' already exists — nothing to do."
    exit 0
fi

# A same-named cert that is NOT a valid identity is a remnant of an aborted
# run (cancelled trust dialog) or a cert that lost its trust setting. Minting
# another would leave codesign matching two "$NAME" certs and failing with
# 'ambiguous identity' on every build — refuse and point at the cleanup.
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✗ A '$NAME' certificate exists but isn't a usable code-signing identity" >&2
    echo "  (leftover from an aborted run, or its trust setting was removed)." >&2
    echo "  Clean it up first, then re-run:" >&2
    echo "    security delete-identity -c \"$NAME\" \"$KEYCHAIN\"" >&2
    exit 1
fi

# The trust-settings write below needs the native macOS password dialog, which
# only exists in a GUI (Aqua) session — over SSH or in CI it fails with "the
# authorization was denied since no user interaction was possible". Fail fast
# BEFORE generating anything, so a headless run can't strand an orphaned
# private key in the login keychain. (Best-effort heuristic: a tmux server
# started at the desk but attached over SSH still passes, and the dialog then
# appears on the physical screen.)
if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || [[ "$(launchctl managername 2>/dev/null)" != "Aqua" ]]; then
    echo "✗ This needs a GUI session on the Mac itself: trusting the certificate" >&2
    echo "  shows a macOS password dialog that cannot appear over SSH or in CI." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▸ Generating a self-signed code-signing certificate ($NAME, valid 10 years)..."
# stderr is captured, not discarded: openssl is the command most likely to vary
# across machines (macOS ships LibreSSL; -addext needs a 2020+ version), and a
# silent `set -e` death here would give the user nothing to go on.
if ! openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:FALSE" 2>"$TMP/openssl.err"; then
    cat "$TMP/openssl.err" >&2
    echo "✗ openssl failed — if it doesn't know -addext, this LibreSSL is too old" >&2
    echo "  (needs macOS 13+, or a Homebrew openssl first in PATH)." >&2
    exit 1
fi

# Import the private key first. -T adds codesign to the key's app ACL, but
# since macOS 10.12 a partition-list check still prompts ONCE on the first
# signing — clicking "Always Allow" there persists for good. (Don't "fix"
# this with set-key-partition-list: it would put the login password on a
# command line for a flow that is interactive by design.)
echo "▸ Importing the private key into the login keychain..."
security import "$TMP/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null

# add-trusted-cert both adds the certificate to the keychain and records the
# user-domain trust setting for the code-signing policy. This is the step
# that prompts for your login password. If it fails (dialog cancelled, wrong
# password), roll back whatever landed so a re-run starts clean: delete the
# identity if the cert paired with the key, else the bare cert. A lone
# imported key has no CLI delete and is inert clutter, not a broken identity
# — only duplicate CERTS cause the 'ambiguous' codesign failure, and the
# remnant check above refuses to mint those.
echo "▸ Trusting it for code signing (macOS will ask for your login password)..."
if ! security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"; then
    security delete-identity -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1 \
        || security delete-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1 \
        || true
    echo "✗ Trust wasn't recorded (dialog cancelled?). No usable identity was" >&2
    echo "  created — re-run when ready. (An inert leftover key may remain; if you" >&2
    echo "  want it gone, delete 'Imported Private Key' in Keychain Access.)" >&2
    exit 1
fi

if security find-identity -v -p codesigning | grep -F "$NAME"; then
    echo "✓ Done. Scripts/build-app.sh now picks '$NAME' up automatically."
    echo "  The FIRST build asks for your login password once more (key access) —"
    echo "  click 'Always Allow' so future builds sign silently. Then reinstall"
    echo "  (Scripts/install.sh), grant Accessibility once more, and the grant"
    echo "  will survive future rebuilds."
else
    echo "✗ The identity didn't materialize — check Keychain Access for '$NAME'." >&2
    exit 1
fi
