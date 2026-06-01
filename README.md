<h1 align="center">Wisp</h1>

<p align="center"><em>The AI-friendly clipboard bezel for macOS — keep the formatting you meant to keep.</em></p>

<p align="center">
  <a href="https://github.com/Attikus-Labs/wisp/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Attikus-Labs/wisp/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-13%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
  <img alt="Dependencies" src="https://img.shields.io/badge/dependencies-zero-brightgreen">
</p>

Wisp is a clipboard built for working with AI tools. Copy comes out of
**Claude Code**, **Codex**, **ChatGPT** and the **Claude** app in wildly
different shapes — terminal text mangled by hard-wraps and box glyphs, rich HTML
from a web answer, raw Markdown from a **Copy** button — and Wisp gives you the
controls to keep exactly the formatting you want.

Press **⌘⇧V** and a translucent bezel shows your most recent clipping; **←/→**
walk through the last 40, or press **/** to search the whole history; then pick
how it lands: **⏎** plain, **⌥⏎** formatted, **⇧⏎** reflowed. It's the classic
Jumpcut/Flycut bezel, rebuilt natively for Apple Silicon, with a security-first design.

> **Why this exists.** [Flycut](https://github.com/TermiT/Flycut) — the clipboard
> manager a lot of us have used for a decade — hasn't had a real update since
> ~2020, runs under Rosetta 2 (it's not a native Apple-Silicon binary), and
> sometimes crashes on recent macOS. The healthiest open-source alternative,
> [Maccy](https://github.com/p0deje/Maccy), is excellent but uses a different
> UX (a searchable list, not the single-clip bezel you cycle with arrows). Wisp
> fills the gap: Flycut's exact bezel feel, native and maintained, and built to
> never leak what you copy.

---

## Three ways to paste

The same clipboard entry can land three different ways. All three keys are always
live on the bezel (the `⇧⏎` hint brightens when a clip looks like terminal output).
The plain text is **always** present on the pasteboard too, so a plain-text editor
gets clean text no matter which mode you choose.

| Key | Mode | Best for | What lands |
|-----|------|----------|------------|
| **⏎** | **Plain** | Anything you want verbatim | Exactly the characters you copied — nothing added, no formatting. |
| **⌥⏎** | **Formatted** | ChatGPT / Claude answers (rich select-and-copy), or any assistant **Copy** button (Markdown) | Real **bold**, *italics*, lists, headings, links and code blocks in rich apps; clean text in plain editors. |
| **⇧⏎** | **Reflowed** | Claude Code, Codex & other terminal output | Terminal noise (ANSI codes, hard wraps, `•`/`▸`/`└` glyphs) cleaned up and re-listed, then pasted formatted; tool-result logs kept verbatim. |

### ⏎ — Plain

What you copied is what lands: the stored plain text, nothing added. The classic
clipboard-manager behavior, and the safe default for code, paths, tokens, or
anything you want byte-for-byte.

### ⌥⏎ — Formatted

Reproduces the **source's** formatting, using the richest representation available —
in order of fidelity:

- **Exact passthrough.** When you *select and copy* from a web answer (the **Claude**
  app, **ChatGPT**, etc.), the source app puts its own HTML on the clipboard. Wisp
  captures that HTML at copy time and re-emits it **verbatim** for a faithful match —
  including tables and structure the app rendered. It's re-emitted *unparsed*, on
  purpose: parsing untrusted HTML could trigger a hidden network fetch, and Wisp never
  touches the network.
- **Markdown rendering.** When there's no source HTML — a plain copy, or an assistant's
  **Copy** button that drops Markdown on the clipboard — Wisp renders that Markdown to
  HTML (and RTF) on the fly at paste time. Supported subset: ATX headings (`#`–`######`),
  **bold**, *italic*, ~~strikethrough~~, `inline code`, fenced code blocks (with language
  hint), `[links](url)` (safe schemes only), blockquotes, ordered & unordered lists, and
  horizontal rules. It's a deliberately small, auditable subset — exactly what chat
  assistants emit — so nested lists flatten to a single level.

Rich targets (Slack, Notes, Mail) get the formatting; plain-text editors (Sublime,
Obsidian) read the plain-text flavor on the same clip and still get clean text. The
captured source HTML is held **in memory only** — never written to disk, and kept
within the per-clip size budget you set ([Memory & limits](#memory--limits), default 2 MB).

### ⇧⏎ — Reflowed

Text copied out of a terminal — **Claude Code**, the **Codex** CLI, anything in
iTerm/WezTerm — arrives wrecked: ANSI colour codes, every line hard-wrapped at the
terminal width, list bullets and box-tree borders reduced to literal `•`/`▸`/`└`
glyphs, all real formatting gone. `⇧⏎` runs a best-effort repair, then pastes the
result formatted:

1. strips ANSI / control sequences,
2. turns leading bullet & box-tree glyphs back into Markdown list items,
3. un-wraps hard-wrapped paragraph lines so they reflow in the target,
4. keeps tool-result blocks (Claude Code's `⎿` output) **verbatim inside a code
   block**, so column-aligned build logs, diffs and trees don't get glued into
   run-on text.

It's openly heuristic and lossy — the original Markdown can't be recovered perfectly —
so it's opt-in per paste and **never** rewrites your saved history. The bezel brightens
the `⇧⏎ reflow` hint only when the current clip actually looks like terminal output, so
it stays out of the way the rest of the time.

## Search your history

Press **/** on the bezel (vi-style) and it turns into a search box over everything
in memory. Type to filter — matching is word-aware and supports multiple terms, so
`google cli` finds clips containing **both** words (in any order), with the matched
text highlighted in each result and a live preview of the highlighted clip below the
list. Move the highlight with **↑/↓** (or **⌃P/⌃N**) and paste it with the same three
keys — **⏎** plain, **⌥⏎** formatted, **⇧⏎** reflowed. **⎋** clears the query, then
steps back to the carousel.

Search only ever reads what's already in memory: nothing is indexed or written to
disk, and passwords / transient copies are filtered out *before* they're ever
stored, so they can never appear in results.

## Features

- **The bezel you know.** One clip at a time, arrows cycle history (looping; direction configurable), `⏎` to
  paste (`⌥⏎` to paste with formatting), `esc` to dismiss, `⌫` to drop an entry.
- **Three ways to paste.** `⏎` plain, `⌥⏎` formatted, `⇧⏎` reflowed — pick how each
  clip lands so AI output keeps the formatting you want. See
  [Three ways to paste](#three-ways-to-paste) above for exactly what each supports.
  The source HTML formatted paste relies on is held **in memory only** — never
  written to disk, and bounded by the per-clip size budget you set.
- **Native & light.** Swift + AppKit, a single tiny native binary, no Dock
  icon — it lives in the menu bar. No Electron, no web view.
- **Zero third-party dependencies.** The only code that touches your clipboard
  is this repo plus Apple's frameworks. Auditable in an afternoon.
- **Secure by design:**
  - **Never records secrets.** Honors the [nspasteboard.org](https://nspasteboard.org)
    privacy markers (`ConcealedType`, `TransientType`, `AutoGeneratedType`) and
    a denylist of known password managers, so passwords copied from 1Password,
    Bitwarden, KeePassXC, etc. never enter the history.
  - **Memory-only, and you set the budget.** History lives in RAM, never on disk —
    quit Wisp (or reboot) and it's gone. Two bounds keep it light, both yours to
    change in the menu: the number of entries (10/20/40/80, default 40) and a
    **per-clip size cap** (default **2 MB**) that applies to every field Wisp retains —
    plain text *and* captured HTML. See [Memory & limits](#memory--limits).
  - **No network. At all.** Wisp has no networking code and no network
    entitlement; nothing you copy can leave your Mac.
  - **Minimal permissions.** One optional grant — Accessibility — used solely to
    synthesize ⌘V when you paste. Nothing else.
- **Open source, MIT.** Notarization-ready release pipeline included.

## Install

Wisp doesn't ship a prebuilt binary yet. Until it's signed & notarized by Apple,
the responsible way to run a clipboard manager is to **build it from source** —
so the app you run is the code you can read here. (Early on that fits the
audience anyway: developers.)

### Build & install from source

Requirements: macOS 13+ and Apple's **Command Line Tools** (`xcode-select --install`).

```sh
git clone https://github.com/Attikus-Labs/wisp
cd wisp
Scripts/install.sh        # builds, installs to /Applications, and launches
```

Because it's built locally, macOS doesn't quarantine it — **no Gatekeeper
prompts**.

> **Prebuilt `.dmg` + Homebrew are coming** once the project has an Apple
> Developer ID for notarization. We deliberately don't ship an *unsigned* binary
> in the meantime: on macOS 15+ it trips a scary "could not verify… malware"
> block and would mean asking you to bypass Gatekeeper — the wrong tradeoff for a
> security-focused clipboard tool.

### First run

1. Launch Wisp — a clipboard icon appears in the menu bar.
2. macOS will ask for **Accessibility** access (System Settings → Privacy &
   Security → Accessibility). Grant it so Wisp can paste for you with ⌘V. If you
   skip it, the chosen clip is still placed on the clipboard — just press ⌘V
   yourself.
3. Optionally enable **Launch at Login** from the menu.

## Usage

| Key | Action |
|-----|--------|
| **⌘⇧V** | Show / hide the bezel |
| **/** | Search the whole history — type to filter (word-aware, multi-term), **↑↓** (or **⌃P/⌃N**) move the highlight, **⏎ / ⌥⏎ / ⇧⏎** paste it, **⎋** clears the query then returns to the carousel |
| **←** or **↑** | Previous (older) entry — loops past the oldest |
| **→** or **↓** | Next (newer) entry — loops past the newest |
| **⏎** | Paste the current entry into the app you came from (plain text) |
| **⌥⏎** | Paste **with formatting** — reproduces the source's formatting (its HTML, if captured) or renders the clip's Markdown, for apps like Slack, Notes & Mail; plain-text editors still get plain text |
| **⇧⏎** | Paste **reflowed** — best-effort cleanup of text copied from a terminal (e.g. Claude Code): strip ANSI, turn bullet/tree glyphs into lists, un-wrap hard-wrapped lines, then paste formatted |
| **esc** | Dismiss |
| **⌫** | Remove the current entry from history |

Menu-bar menu: show clipboard, clear history, history size (10/20/40/80), **Max Clip
Size** (per-clip memory budget — 1/2/5/10/50 MB or Unlimited, default 2 MB; applies to
text and captured HTML), arrow direction (which arrow walks back to previous copies),
launch at login, and the Auto-Paste Permission (Accessibility) status.

## Security

Security is the point of this project, not an afterthought. The full threat
model is in **[docs/SECURITY.md](docs/SECURITY.md)**. The short version:

| Concern | Wisp's answer |
|---|---|
| Passwords ending up in history | Skipped via nspasteboard markers + password-manager denylist |
| History persisted to disk | Never — memory-only; quit or reboot and it's gone |
| Runaway memory use | Bounded on both axes you control: entry count (10/20/40/80) and a per-clip size cap (default 2 MB, covers text + captured HTML, up to Unlimited) — see [Memory & limits](#memory--limits) |
| Data leaving your machine | Impossible — no networking code, no network entitlement |
| Supply-chain risk | Zero third-party dependencies |
| Excess permissions | Accessibility only, only for paste; **not** sandboxed because auto-paste requires synthesizing keys into other apps (the same posture Maccy takes) |

## Memory & limits

Wisp's whole history lives in RAM (never on disk), so it's worth being deliberate
about how much RAM it may use — and that knob is **yours**. There are two bounds, both
in the menu:

- **History size** — how many entries to keep: **10 / 20 / 40 / 80** (default 40).
  Oldest entries fall off the end as new ones arrive; re-copying the same text just
  moves it back to the front instead of adding a duplicate.
- **Max clip size** — a per-clip byte budget that applies to **every field Wisp
  retains: the plain text *and* the captured rich HTML**. Choose **1 / 2 / 5 / 10 /
  50 MB** or **Unlimited** (default **2 MB**).

How the per-clip cap behaves:

| Situation | What happens |
|---|---|
| A clip's **text** is over the cap | Not remembered at all — it stays on the system clipboard, so a normal **⌘V still works**; Wisp just won't add it to history. |
| A clip's **HTML** is over the cap (text under it) | The HTML is dropped, the entry is kept as plain text, and `⌥⏎` falls back to rendering the clip's Markdown. |
| **Unlimited** | No cap — Wisp keeps whatever you copy, however large. |

So the worst-case memory for the history is roughly *history size × max clip size* (≈
80 MB at the defaults, ≈ 4 GB at 80 × 50 MB), entirely under your control. Copying very
large texts is genuinely useful — diffs, logs, whole files — and Wisp lets you keep them
when you decide that's worth the memory: just raise the cap. Prefer a featherweight
clipboard? Drop it to 1 MB. Either way you're trading memory for history on purpose, not
by accident. Changing the cap affects clips captured from then on; **Clear History**
drops anything already held.

## Development

Building the app needs only Apple's **Command Line Tools**; running the test
suite (Swift Testing) needs a full Xcode toolchain.

```sh
Scripts/run.sh                 # build & launch the debug app
Scripts/build-app.sh release   # build a release .app into dist/
Scripts/install.sh             # build & install to /Applications
swift test                     # unit tests (requires full Xcode)
```

## How it works

```
Sources/
  WispCore/                 ← all logic + UI (unit-tested library)
    ClipboardMonitor.swift  ← polls NSPasteboard.changeCount (~0.5s)
    PrivacyFilter.swift     ← the "never record secrets" rules
    ClipboardHistory.swift  ← 40-item, newest-first, memory-only ring
    GlobalHotkey.swift      ← ⌘⇧V via Carbon RegisterEventHotKey (no deps)
    Bezel*.swift            ← the borderless floating HUD + arrow navigation
    Paster.swift            ← sets the pasteboard, synthesizes ⌘V
    MarkdownRenderer.swift  ← Markdown → HTML for ⌥⏎ formatted paste (deps-free)
    TerminalText.swift      ← ⇧⏎ best-effort reflow of terminal copies (deps-free)
    AppDelegate.swift       ← menu bar wiring
  Wisp/                     ← tiny executable entry point
```

macOS has no "clipboard changed" notification, so — like every clipboard manager
— Wisp watches `changeCount` on a light, battery-friendly timer.

## Roadmap

- [ ] App icon
- [ ] User-rebindable hotkey
- [ ] Tighten to Swift 6 strict-concurrency language mode
- [ ] Reproducible-build verification
- [ ] Optional pinned/favorite clips

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Standing on the shoulders of [Jumpcut](https://github.com/snark/jumpcut) and
[Flycut](https://github.com/TermiT/Flycut) (the bezel interaction), with privacy
behavior guided by [nspasteboard.org](https://nspasteboard.org) and inspiration
from [Maccy](https://github.com/p0deje/Maccy).

## License

[MIT](LICENSE) © 2026 Julien Brinas.

---

<sub>Replace the `Attikus-Labs/wisp` slug throughout (README badges, `Casks/wisp.rb`,
`Sources/WispCore/AppInfo.swift`, the workflows) if your GitHub owner/repo name
differs.</sub>
