---
description: Review the current changes against Wisp's principles, build & test, then open a PR — refuses to submit if a gate fails
argument-hint: "[optional PR title / extra context]  — defaults to a title derived from the diff"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git branch:*), Bash(git checkout:*), Bash(git switch:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git remote:*), Bash(swift build:*), Bash(swift test:*), Bash(Scripts/build-app.sh:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh repo view:*), Bash(grep:*), Read, Grep, Glob, Skill
---

Open a pull request for the current changes — but only after they pass review,
build, and test. Wisp is a clipboard manager: a bad PR here can leak everything
a user copies. So this command is a **gate**, not a shortcut. If any step below
fails, **stop and report — do not commit, push, or open the PR.**

Work through the steps in order. `$ARGUMENTS`, if present, is the PR title /
extra context the user wants used.

---

## 1. Preflight

```sh
git rev-parse --show-toplevel
git branch --show-current
git status --porcelain
git remote get-url origin
```

- If the working tree is clean (nothing staged or unstaged and no untracked
  source changes), there is nothing to PR — say so and stop.
- Note the base branch (the repo's default, usually `main`) and whether you are
  currently **on** it. You'll branch off it in step 5.

## 2. Code review (delegate + Wisp principles gate)

First run the project's reviewer on the diff:

- Invoke the **`/code-review`** skill (use the Skill tool) at `high` effort. Let
  it surface correctness bugs and quality issues. Treat its blocking findings as
  blocking here too.

Then apply Wisp's **non-negotiable principles** as hard gates. These come from
`CONTRIBUTING.md` and `docs/SECURITY.md` — read them if unsure. Inspect the diff
(`git diff` for unstaged, `git diff --staged` for staged) and **BLOCK the PR** if
the change introduces any of:

- **Networking of any kind.** Wisp ships with no network code and no network
  entitlement ("don't phone home"). Search the diff:
  ```sh
  git diff | grep -nE '^\+' | grep -nEi 'URLSession|URLRequest|NW(Connection|Listener|Path)|Network\.framework|CFSocket|getaddrinfo|dataTask|http://|https://|telemetry|analytics'
  ```
  Hits in *added* lines (outside comments/markdown links) are a hard block.
- **Persisting clipboard contents anywhere.** History is memory-only; the *only*
  thing allowed in `UserDefaults` is the history **size**, never clipboard text.
  Block any write of clip text to disk or defaults:
  ```sh
  git diff | grep -nE '^\+' | grep -nEi 'write\(to:|FileManager|homeDirectoryForCurrentUser|Library/Logs|\.set\(.*forKey|stringArray\(forKey|Data\(contentsOf|persist|restoreHistory'
  ```
  Investigate every hit. Persisting history text, dumping it to a log, or caching
  it is a hard block.
- **New third-party dependencies.** `Package.swift` must keep `dependencies: []`
  on every target. Any added package is a hard block.
- **A weakened privacy filter.** Removing markers/denylist entries, or recording
  where Wisp previously skipped, is a block unless the user explicitly intends it.
- **Leftover debug / WIP code.** Block on `TODO: remove before merge`, commented-
  out blocks, stray scaffolding (`# trailing edit`, throwaway `print(...)`,
  "screenshot"/"forever"/"debug" helpers), or anything the author flagged as
  temporary:
  ```sh
  git diff | grep -nEi 'remove before merge|trailing edit|FIXME|XXX|keepOpenForever|dumpHistory|for screenshots|debug(ging)?'
  ```
- **New compiler warnings** (see step 3 — `swift build` must be clean).

For anything you block on, point at the exact `file:line` and the principle it
violates. If the user wants to proceed anyway, the fix is to *change the code*,
not to bypass the gate.

## 3. Build, test, lint

Wisp has no SwiftLint config — "lint" here means **`swift build` compiles clean
with no new warnings** (per `CONTRIBUTING.md`). Run, in order:

```sh
swift build 2>&1 | tee /tmp/wisp-build.log
swift test
```

- **Build must succeed with zero warnings.** Any warning introduced by the diff
  is a block — surface it.
- `swift test` uses **Swift Testing**, which needs a full Xcode toolchain. If
  `xcode-select -p` points at `CommandLineTools` only, `swift test` may not run
  locally. In that case: say so explicitly, confirm `swift build` is clean, and
  note that the test suite runs in CI (`.github/workflows/ci.yml`) on macOS — do
  **not** silently claim tests passed.
- Optionally sanity-check the bundle as CI does: `Scripts/build-app.sh release`.

## 4. Decision gate

Only continue if **every** check above passed (or, for `swift test`, the
CLT-only fallback was clearly reported). If anything is blocking:
**stop here.** Report the findings grouped by severity, with `file:line`, and ask
the user how they want to proceed. Do not commit, push, or open a PR.

## 5. Branch, commit, push

- If you're **on the base branch** (`main`), create a feature branch first — never
  PR from `main`. Derive a short kebab-case name from the change, e.g.
  `git switch -c fix/bezel-release-crash`.
- Stage and commit with a focused message (subject ≤ ~72 chars, body explaining
  *why*). End the commit message with:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```
- Push with upstream tracking: `git push -u origin HEAD`.

## 6. Open the PR

```sh
gh pr create --base <base> --title "<title>" --body "<body>"
```

Write the body from the actual diff:
- **Summary** — what changed and why.
- **Principle check** — one line confirming: no networking, no disk persistence
  of clipboard text, no new deps, privacy filter unchanged. This is the bar
  reviewers care about most.
- **Testing** — exactly what you ran (`swift build` clean; `swift test` result or
  the CLT-only note).
- End the body with:
  ```
  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```

Then report the PR URL.

---

Notes for you (the agent):
- This command's job is to be **trustworthy**, not fast. Catching a telemetry
  call or a history-to-disk write is a success, not a failure — that's the point.
- Never `git add -A` blindly; stage only the files that belong in this PR.
- If `gh` isn't authenticated, stop and tell the user to run `gh auth login`
  (suggest typing `! gh auth login` in the prompt).
- Surface real errors; don't retry a failed step blindly.
