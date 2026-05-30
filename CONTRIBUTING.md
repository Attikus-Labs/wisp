# Contributing to Wisp

Thanks for your interest! Wisp aims to stay **small, native, dependency-free,
and secure**. Please keep changes aligned with that.

## Ground rules

- **No third-party runtime dependencies.** This is a deliberate security
  property. System frameworks (AppKit, Carbon, ServiceManagement, …) only.
- **Never persist clipboard contents to disk**, and never add networking. If you
  think you need either, open an issue first.
- Keep the privacy filter conservative: when in doubt, *don't* record.

## Building & testing

```sh
swift build              # Command Line Tools are enough
Scripts/run.sh           # build + launch the .app
swift test               # requires a full Xcode toolchain (Swift Testing)
```

> Tests are written with **Swift Testing** (`import Testing`). They run in CI on
> macOS runners and locally when `xcode-select` points at a full Xcode. With only
> the Command Line Tools you can still build and run the app.

## Project layout

- `Sources/WispCore/` — all logic and UI, as a testable library.
- `Sources/Wisp/` — the executable entry point (one file).
- `Tests/WispCoreTests/` — Swift Testing suites.
- `Scripts/` — build / sign / notarize / dmg helpers.
- `docs/` — security model and release runbook.

## Style

Match the surrounding code: clear names, comments that explain *why*, and small
focused types. Run `swift build` clean (no new warnings) before opening a PR.

## Security

Found a vulnerability? See [docs/SECURITY.md](docs/SECURITY.md#reporting-a-vulnerability)
— please report privately, not via a public issue.
