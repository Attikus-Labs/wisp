import Foundation

/// Best-effort cleanup of text copied from a terminal (e.g. Claude Code).
///
/// Terminal copies are lossy by the time they reach the clipboard: the renderer
/// has already turned Markdown into styled glyphs, ANSI colour codes are stripped,
/// lines are HARD-wrapped at the terminal width (every visual wrap becomes a real
/// newline), and list bullets / box borders survive only as literal Unicode
/// glyphs. The original Markdown can't be recovered faithfully — so this is openly
/// a heuristic "make it presentable again" pass, offered behind an opt-in key
/// (⇧⏎) and never applied automatically to your history.
///
/// What it does: strips stray ANSI / control sequences, turns leading bullet and
/// box-tree glyphs into Markdown list markers, and de-wraps hard-wrapped paragraph
/// lines so they reflow in the target. Fenced and indented code are left intact.
///
/// One thing it deliberately does NOT reflow: a tool-result region (a block that
/// contains Claude Code's ⎿ result connector, U+23BF). That output is 2-D
/// structure — column-aligned build logs, trees, status lines — not prose, so
/// de-wrapping it would glue legitimately-separate lines into a run-on. We instead
/// keep the whole block verbatim inside a fenced code block, so the target renders
/// it as monospace with every line break and column intact.
///
/// Foundation-only: pure and unit-testable without a pasteboard.
enum TerminalText {
    private static let bulletGlyphs = "•◦▪‣∙●○♦◆▸▶"

    private static func isBoxDrawing(_ scalar: Unicode.Scalar) -> Bool {
        (0x2500...0x257F).contains(scalar.value) // U+2500–257F: borders, trees
    }

    /// The tool-result branch connector Claude Code emits (⎿, U+23BF). It sits
    /// *outside* the box-drawing range, so it needs its own check. A block
    /// containing one is treated as verbatim terminal structure, not prose.
    private static func isResultConnector(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x23BF
    }

    /// Heuristic: does this look like it came out of a terminal? Tuned to stay
    /// quiet for ordinary Markdown (which uses `-`/`*`/`#`, not glyphs), so the
    /// reflow affordance only surfaces when it's actually relevant.
    static func looksLikeTerminalOutput(_ text: String) -> Bool {
        if text.contains("\u{001B}") { return true } // ESC — an ANSI sequence
        for scalar in text.unicodeScalars where isBoxDrawing(scalar) || isResultConnector(scalar) { return true }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if let first = trimmed.first, bulletGlyphs.contains(first),
               trimmed.dropFirst().first == " " {
                return true
            }
        }
        return false
    }

    /// Reflow terminal-copied text into cleaner Markdown. Lossy on purpose.
    static func reflow(_ text: String) -> String {
        let stripped = stripControlSequences(text)
        let rawLines = stripped.replacingOccurrences(of: "\r\n", with: "\n")
                               .replacingOccurrences(of: "\r", with: "\n")
                               .components(separatedBy: "\n")

        // Group into blank-line-delimited blocks. A block that's a ⎿ tool-result
        // region is kept verbatim (fenced); everything else is de-wrapped as prose.
        // We carry the raw line beside its normalized form so the verbatim path can
        // emit the original glyphs/indentation while the prose path uses the cleaned
        // markers — and we split blocks on the *normalized* blank so a content-less
        // bullet (`•` → "") still separates paragraphs, exactly as before.
        var out: [String] = []
        var rawBlock: [String] = []
        var normBlock: [String] = []
        func flush() {
            guard !normBlock.isEmpty else { return }
            out.append(blockIsStructural(rawBlock) ? protectAsFence(rawBlock)
                                                   : dewrapBlock(normBlock))
            rawBlock = []; normBlock = []
        }
        var i = 0
        while i < rawLines.count {
            let raw = rawLines[i]
            let norm = normalizeLine(raw)
            if norm.trimmingCharacters(in: .whitespaces).isEmpty {
                // A blank line normally ends a block. But a ⎿ tool-result region
                // routinely contains blank lines (multi-section build/test logs,
                // diffs); splitting there would fence only the head and de-wrap the
                // tail into the very run-on this feature exists to prevent. So while
                // we're inside a result region that clearly continues past the blank
                // — the next non-blank line is still indented to the connector — keep
                // the blank inside the block instead of flushing.
                if blockIsStructural(rawBlock),
                   resultRegionContinues(after: i, in: rawLines,
                                         anchor: resultAnchorIndent(rawBlock)) {
                    rawBlock.append(raw)
                    normBlock.append(norm)
                } else {
                    flush()
                    out.append("") // preserve the paragraph break
                }
            } else {
                rawBlock.append(raw)
                normBlock.append(norm)
            }
            i += 1
        }
        flush()

        // Collapse runs of paragraph-break markers to a single blank line and trim
        // the ends. Done on the block array — not as a global `\n{3,}` regex — so
        // blank lines kept verbatim inside a fenced result block survive untouched.
        var collapsed: [String] = []
        for entry in out where !(entry.isEmpty && (collapsed.last?.isEmpty ?? true)) {
            collapsed.append(entry)
        }
        while collapsed.last?.isEmpty == true { collapsed.removeLast() }
        return collapsed.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Steps

    private static func stripControlSequences(_ text: String) -> String {
        var s = text
        // CSI sequences (colour, cursor moves): ESC [ … final-byte.
        s = s.replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
                                   with: "", options: .regularExpression)
        // OSC sequences: ESC ] … (BEL | ESC \).
        s = s.replacingOccurrences(of: "\u{001B}\\][^\u{0007}\u{001B}]*(\u{0007}|\u{001B}\\\\)",
                                   with: "", options: .regularExpression)
        // Any other lone ESC.
        s = s.replacingOccurrences(of: "\u{001B}", with: "")
        // Remaining C0 control chars except tab/newline.
        return String(s.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\n" || $0 == "\t" })
    }

    /// Trim a line's trailing padding and convert a leading bullet / box-tree glyph
    /// into a Markdown list marker.
    private static func normalizeLine(_ raw: String) -> String {
        var line = raw
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }

        var idx = line.startIndex
        var leadingSpaces = 0
        while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" {
            leadingSpaces += 1
            idx = line.index(after: idx)
        }
        let afterIndent = String(line[idx...])
        let indent = String(repeating: " ", count: leadingSpaces)

        // Leading box-drawing run (tree/branch glyphs) → a list item, indent kept.
        if let firstScalar = afterIndent.unicodeScalars.first, isBoxDrawing(firstScalar) {
            var rest = afterIndent
            while let f = rest.unicodeScalars.first, isBoxDrawing(f) || f == " " {
                rest.removeFirst()
            }
            return rest.isEmpty ? "" : indent + "- " + rest
        }

        // Leading bullet glyph → Markdown list marker, indent kept. Accept "• text"
        // (glyph then space); a content-less bullet is dropped.
        if let first = afterIndent.first, bulletGlyphs.contains(first) {
            let afterGlyph = afterIndent.dropFirst()
            if afterGlyph.isEmpty { return "" }
            if afterGlyph.first == " " { return indent + "- " + afterGlyph.dropFirst() }
        }
        return line
    }

    /// De-wrap one block (no internal blank lines): join wrapped continuation lines,
    /// but keep list items / headings as separate lines and leave code intact.
    private static func dewrapBlock(_ block: [String]) -> String {
        // Leave fenced or fully-indented code untouched — joining it corrupts code.
        if block.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) {
            return block.joined(separator: "\n")
        }
        if block.allSatisfy({ $0.hasPrefix("    ") || $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return block.joined(separator: "\n")
        }

        var logical: [String] = []
        for line in block {
            if logical.isEmpty || startsListItem(line) || startsBlockLevel(line) {
                logical.append(line)
            } else {
                // Wrapped continuation of the previous logical line.
                let prev = logical.removeLast()
                let joiner = prev.hasSuffix(" ") ? "" : " "
                logical.append(prev + joiner + line.trimmingCharacters(in: .whitespaces))
            }
        }
        return logical.joined(separator: "\n")
    }

    /// Is this block terminal *structure* (a ⎿ tool-result region) rather than
    /// prose? High-precision on purpose: it fires only on the ⎿ connector, so
    /// ordinary lists, bullets and box-trees stay on the prose / de-wrap path.
    private static func blockIsStructural(_ rawLines: [String]) -> Bool {
        rawLines.contains { lineOpensResult($0) }
    }

    /// Leading-whitespace width of the first ⎿ connector line in the block — the
    /// indentation a continuation must reach to count as part of the same region.
    private static func resultAnchorIndent(_ rawLines: [String]) -> Int {
        for line in rawLines where lineOpensResult(line) {
            return line.count - line.drop { $0 == " " || $0 == "\t" }.count
        }
        return 0
    }

    /// Does the ⎿ result region continue past the blank line at `blankIdx`? True
    /// when the next non-blank line is still indented at least to the connector
    /// (region body), false when it dedents out (a new paragraph / ● turn) or only
    /// blank lines remain. `max(anchor, 1)` guards a column-0 connector from
    /// swallowing the following unindented paragraph.
    private static func resultRegionContinues(after blankIdx: Int, in rawLines: [String], anchor: Int) -> Bool {
        var j = blankIdx + 1
        while j < rawLines.count {
            let rest = rawLines[j].drop { $0 == " " || $0 == "\t" }
            if rest.isEmpty { j += 1; continue } // skip further blank lines
            return (rawLines[j].count - rest.count) >= max(anchor, 1)
        }
        return false
    }

    /// Whether a line's first non-whitespace glyph is the ⎿ result connector.
    private static func lineOpensResult(_ line: String) -> Bool {
        line.drop { $0 == " " || $0 == "\t" }.unicodeScalars.first.map(isResultConnector) ?? false
    }

    /// Emit a structural block verbatim inside a fenced code block, so the target
    /// renders it as monospace `<pre><code>` — every line break (blank lines
    /// included), column, glyph (●, ⎿, …) and indentation preserved. Only trailing
    /// padding is trimmed; leading indentation (the alignment) is never touched.
    /// The fence is a run of backticks one longer than the longest backtick run
    /// *anywhere* in the body, so no line of the captured output can close the block
    /// early (CommonMark's closing-fence rule) — even output that itself shows
    /// ``` / ~~~, and regardless of any leading whitespace the renderer would trim.
    private static func protectAsFence(_ rawLines: [String]) -> String {
        let body = rawLines.map { line -> String in
            var s = line
            while let last = s.last, last == " " || last == "\t" { s.removeLast() }
            return s
        }.joined(separator: "\n")
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(body) + 1))
        return "\(fence)\n\(body)\n\(fence)"
    }

    /// Longest run of consecutive backticks anywhere in `s`. Sizing the fence past
    /// this guarantees no line of the captured output can form a closing fence —
    /// it's a superset of every line-leading run, so leading-whitespace differences
    /// between this producer and the renderer's matcher can't reopen the hole.
    private static func longestBacktickRun(_ s: String) -> Int {
        var longest = 0, run = 0
        for ch in s {
            if ch == "`" { run += 1; longest = max(longest, run) } else { run = 0 }
        }
        return longest
    }

    private static func startsListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
        return t.range(of: "^\\d+[.)]\\s", options: .regularExpression) != nil
    }

    private static func startsBlockLevel(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("#") || t.hasPrefix(">") || t.hasPrefix("~~~")
    }
}
