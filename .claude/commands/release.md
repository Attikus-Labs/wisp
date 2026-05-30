---
description: Build a Wisp .dmg and publish it as a GitHub Release (unsigned for now; auto-notarizes once a Developer ID is configured)
argument-hint: "[version]  e.g. 0.1.1 — defaults to the version in Resources/Info.plist"
allowed-tools: Bash(Scripts/release.sh:*), Bash(gh release view:*), Bash(gh release list:*), Read
---

Cut a Wisp release by running the deterministic pipeline:

```
Scripts/release.sh $ARGUMENTS
```

That script builds the app, packages a `.dmg`, generates checksums, and
creates/updates the GitHub Release. It **auto-notarizes if** signing credentials
are present in the environment (`SIGN_IDENTITY` + notary creds, see
`docs/RELEASING.md`); otherwise it ships an **unsigned** build whose release
notes tell users to right-click → Open past Gatekeeper.

After it finishes:

1. Report the release URL printed at the end (`==> Done: <url>`), and say which
   version was released and whether it was **signed/notarized** or **unsigned**.
2. If it was unsigned, briefly remind the user that one-click installs need an
   Apple Developer ID, and that re-running `/release` after setting
   `SIGN_IDENTITY` + notary creds will publish a notarized dmg automatically — no
   change to this command.

Notes for you (the agent):
- Pass `$ARGUMENTS` straight through as the version only if the user supplied
  one; with no argument the script uses `Resources/Info.plist`.
- Do **not** bump the version yourself. If the user wants a new version, first
  edit `CFBundleShortVersionString` (and bump the integer `CFBundleVersion`) in
  `Resources/Info.plist`, then run the script.
- If `Scripts/release.sh` fails, surface the actual error; don't retry blindly.
