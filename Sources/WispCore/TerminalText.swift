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
/// Foundation-only: pure and unit-testable without a pasteboard.
enum TerminalText {
    private static let bulletGlyphs = "•◦▪‣∙●○♦◆▸▶"

    private static func isBoxDrawing(_ scalar: Unicode.Scalar) -> Bool {
        (0x2500...0x257F).contains(scalar.value) // U+2500–257F: borders, trees
    }

    /// Heuristic: does this look like it came out of a terminal? Tuned to stay
    /// quiet for ordinary Markdown (which uses `-`/`*`/`#`, not glyphs), so the
    /// reflow affordance only surfaces when it's actually relevant.
    static func looksLikeTerminalOutput(_ text: String) -> Bool {
        if text.contains("\u{001B}") { return true } // ESC — an ANSI sequence
        for scalar in text.unicodeScalars where isBoxDrawing(scalar) { return true }
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
        let lines = stripped.replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
                            .components(separatedBy: "\n")
                            .map(normalizeLine)

        // Group into blank-line-delimited blocks and de-wrap each.
        var out: [String] = []
        var block: [String] = []
        func flush() {
            if !block.isEmpty { out.append(dewrapBlock(block)); block = [] }
        }
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                out.append("") // preserve the paragraph break
            } else {
                block.append(line)
            }
        }
        flush()

        // Collapse runs of blank lines and trim the ends.
        return out.joined(separator: "\n")
                  .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
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
