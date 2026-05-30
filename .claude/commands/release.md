---
description: Publish a Wisp release — source-only now (no binary); auto-builds a notarized .dmg once a Developer ID is configured
argument-hint: "[version]  e.g. 0.1.1 — defaults to the version in Resources/Info.plist"
allowed-tools: Bash(Scripts/release.sh:*), Bash(gh release view:*), Bash(gh release list:*), Read
---

Cut a Wisp release by running the deterministic pipeline:

```
Scripts/release.sh $ARGUMENTS
```

By default this publishes a **source-only** GitHub Release: it verifies the tag
compiles, then creates/updates the release with build-from-source notes and lets
GitHub attach the auto-generated source archives. No unsigned binary is shipped —
for a clipboard tool, telling users to bypass Gatekeeper is the wrong tradeoff.

**The moment signing credentials are present** in the environment (`SIGN_IDENTITY`
+ notary creds — see `docs/RELEASING.md`), the same command instead builds,
**notarizes**, and attaches a `.dmg` + checksums. So "add binaries later" needs no
change to this command.

After it runs:
1. Report the release URL (`==> Done: <url>`) and say whether it was a
   **source-only** or a **notarized binary** release, and which version.
2. If source-only, note that prebuilt binaries arrive once an Apple Developer ID
   is set up.

Notes for you (the agent):
- Pass `$ARGUMENTS` through as the version only if the user supplied one; with no
  argument the script uses `Resources/Info.plist`.
- Don't bump the version yourself; if the user wants a new one, edit
  `CFBundleShortVersionString`/`CFBundleVersion` in `Resources/Info.plist` first.
- If `Scripts/release.sh` fails, surface the real error; don't retry blindly.
