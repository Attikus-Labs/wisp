import Foundation

/// Minimal, dependency-free Markdown → HTML renderer.
///
/// Wisp stays *text-only*: the history holds plain strings, never rich data. When
/// you ask for a formatted paste (⌥⏎), we render the stored text — which from
/// Claude, ChatGPT and friends is Markdown — into HTML on the fly. Rich targets
/// (Slack, Notes, Mail…) then show real bold / lists / code, while plain-text
/// targets (Sublime, Obsidian) still receive the original Markdown via the
/// plain-text flavor on the pasteboard. The HTML is generated here at paste time
/// and never retained.
///
/// Scope is the common Markdown subset chat assistants emit: ATX headings, bold,
/// italic, strikethrough, inline code, links, fenced code blocks, blockquotes,
/// unordered / ordered lists, horizontal rules, and paragraphs. Nested lists are
/// flattened to a single level. This is deliberately *not* a full CommonMark
/// implementation — small enough to audit, good enough for assistant output.
///
/// Deliberately built on Foundation only (no AppKit), so it is pure, off-main-
/// thread safe, and unit-testable without a pasteboard.
enum MarkdownRenderer {
    /// Render Markdown to an HTML *fragment* (no surrounding `<html>/<body>`).
    static func html(from markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
                                 .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [String] = []
        var i = 0

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // Fenced code block: ``` or ~~~ … verbatim, no inline formatting.
            if let fence = fenceMarker(trimmed) {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count,
                      fenceMarker(lines[i].trimmingCharacters(in: .whitespaces)) != fence {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // consume the closing fence (if present)
                let cls = lang.isEmpty ? "" : " class=\"language-\(escapeAttribute(lang))\""
                blocks.append("<pre><code\(cls)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            // Blank line: block separator.
            if trimmed.isEmpty { i += 1; continue }

            // Horizontal rule: ---, ***, ___ (3+ of the same char).
            if isHorizontalRule(trimmed) {
                blocks.append("<hr>")
                i += 1
                continue
            }

            // ATX heading: # … ######.
            if let (level, text) = atxHeading(trimmed) {
                blocks.append("<h\(level)>\(inline(text))</h\(level)>")
                i += 1
                continue
            }

            // Blockquote: one or more leading `>` lines, rendered recursively.
            if trimmed.hasPrefix(">") {
                var inner: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var stripped = String(t.dropFirst())
                    if stripped.hasPrefix(" ") { stripped.removeFirst() }
                    inner.append(stripped)
                    i += 1
                }
                blocks.append("<blockquote>\(html(from: inner.joined(separator: "\n")))</blockquote>")
                continue
            }

            // Unordered list: -, *, + markers (flattened, single level).
            if unorderedItem(raw) != nil {
                var items: [String] = []
                while i < lines.count, let text = unorderedItem(lines[i]) {
                    items.append("<li>\(inline(text))</li>")
                    i += 1
                }
                blocks.append("<ul>\(items.joined())</ul>")
                continue
            }

            // Ordered list: `1.` / `1)` markers (flattened, single level).
            if orderedItem(raw) != nil {
                var items: [String] = []
                while i < lines.count, let text = orderedItem(lines[i]) {
                    items.append("<li>\(inline(text))</li>")
                    i += 1
                }
                blocks.append("<ol>\(items.joined())</ol>")
                continue
            }

            // Paragraph: gather consecutive lines until a blank or a new block.
            var para: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty || startsBlock(t, rawLine: lines[i]) { break }
                para.append(t)
                i += 1
            }
            // Keep single line breaks as <br> (GitHub-style), so pasted assistant
            // text — which uses newlines as real breaks, not Markdown soft-wraps —
            // doesn't collapse into one run-on paragraph.
            blocks.append("<p>\(para.map(inline).joined(separator: "<br>\n"))</p>")
        }

        return blocks.joined(separator: "\n")
    }

    // MARK: - Block helpers

    /// Returns "```" or "~~~" when `line` opens/closes a fenced code block.
    private static func fenceMarker(_ line: String) -> String? {
        for fence in ["```", "~~~"] where line.hasPrefix(fence) { return fence }
        return nil
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3,
              let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func atxHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = String(line.dropFirst(level))
        guard rest.first == " " || rest.isEmpty else { return nil } // require "# " not "#text"
        // Trailing #'s are decorative in ATX headings — drop them.
        let text = rest.trimmingCharacters(in: .whitespaces)
                       .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                       .trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    /// The item text if `line` is an unordered-list item (`- `, `* `, `+ `).
    private static func unorderedItem(_ line: String) -> String? {
        firstGroup(unorderedItemRegex, in: line)
    }

    /// The item text if `line` is an ordered-list item (`1. ` / `1) `).
    private static func orderedItem(_ line: String) -> String? {
        firstGroup(orderedItemRegex, in: line)
    }

    /// Does this (already-trimmed) line begin a new block, so paragraph
    /// accumulation must stop?
    private static func startsBlock(_ trimmed: String, rawLine: String) -> Bool {
        if fenceMarker(trimmed) != nil { return true }
        if isHorizontalRule(trimmed) { return true }
        if atxHeading(trimmed) != nil { return true }
        if trimmed.hasPrefix(">") { return true }
        if unorderedItem(rawLine) != nil { return true }
        if orderedItem(rawLine) != nil { return true }
        return false
    }

    // MARK: - Inline formatting

    // Compiled once — NSRegularExpression has no implicit pattern cache, and these
    // run per line/block during a render.
    private static let unorderedItemRegex = try! NSRegularExpression(pattern: "^\\s*[-*+]\\s+(.*)$")
    private static let orderedItemRegex   = try! NSRegularExpression(pattern: "^\\s*\\d+[.)]\\s+(.*)$")
    private static let codeSpanRegex      = try! NSRegularExpression(pattern: "`([^`]+)`")
    private static let linkRegex          = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)")
    private static let boldStarRegex      = try! NSRegularExpression(pattern: "\\*\\*(\\S(?:.*?\\S)?)\\*\\*")
    private static let boldUnderscoreRegex = try! NSRegularExpression(pattern: "(?<!\\w)__(\\S(?:.*?\\S)?)__(?!\\w)")
    private static let strikeRegex        = try! NSRegularExpression(pattern: "~~(\\S(?:.*?\\S)?)~~")
    private static let italicStarRegex    = try! NSRegularExpression(pattern: "\\*(\\S(?:[^*]*?\\S)?)\\*")
    private static let italicUnderscoreRegex = try! NSRegularExpression(pattern: "(?<!\\w)_(\\S(?:[^_]*?\\S)?)_(?!\\w)")

    private static func inline(_ raw: String) -> String {
        // Drop any pre-existing sentinel scalars so our code-span placeholders can't
        // collide with user text. U+E000/U+E001 are Private Use Area — safe to omit
        // from the rich rendering; the plain-text flavor keeps the original intact.
        let text = raw.replacingOccurrences(of: "\u{E000}", with: "")
                      .replacingOccurrences(of: "\u{E001}", with: "")

        // 1. Pull out inline-code spans first so their contents are never treated
        //    as Markdown (and are HTML-escaped exactly once).
        var codeSpans: [String] = []
        var working = replaceMatches(codeSpanRegex, in: text) { groups in
            codeSpans.append("<code>\(escape(groups[1]))</code>")
            return "\u{E000}\(codeSpans.count - 1)\u{E001}"
        }

        // 2. Escape the remaining literal text.
        working = escape(working)

        // 3. Links: [text](url). The text is already escaped; the URL needs its
        //    attribute-delimiter quotes neutralised, and an unsafe scheme
        //    (javascript:, file:, …) drops the anchor entirely — defense-in-depth so
        //    a pasted link can never become a live script/file reference.
        working = replaceMatches(linkRegex, in: working) { groups in
            guard isSafeURL(groups[2]) else { return groups[1] }
            let href = groups[2].replacingOccurrences(of: "\"", with: "&quot;")
            return "<a href=\"\(href)\">\(groups[1])</a>"
        }

        // 4. Emphasis. Bold before italic; require non-space edges to avoid
        //    italicising stray `*` / `_` used as literal characters. Underscore
        //    emphasis must not fire mid-word (foo_bar_baz).
        working = wrap(in: working, boldStarRegex, tag: "strong")
        working = wrap(in: working, boldUnderscoreRegex, tag: "strong")
        working = wrap(in: working, strikeRegex, tag: "del")
        working = wrap(in: working, italicStarRegex, tag: "em")
        working = wrap(in: working, italicUnderscoreRegex, tag: "em")

        // 5. Restore code spans.
        for (idx, span) in codeSpans.enumerated() {
            working = working.replacingOccurrences(of: "\u{E000}\(idx)\u{E001}", with: span)
        }
        return working
    }

    private static func wrap(in text: String, _ re: NSRegularExpression, tag: String) -> String {
        replaceMatches(re, in: text) { groups in "<\(tag)>\(groups[1])</\(tag)>" }
    }

    // MARK: - Escaping & regex

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Whether a link URL is safe to emit as an `href`. Relative URLs are fine; for
    /// absolute URLs only a small allowlist of benign schemes is permitted, so
    /// `javascript:`, `file:`, `data:`, etc. never become live anchors.
    private static func isSafeURL(_ url: String) -> Bool {
        guard let colon = url.firstIndex(of: ":") else { return true } // relative URL
        // A path/query/fragment before the colon means it isn't a scheme separator.
        for ch in url[url.startIndex..<colon] where "/?#".contains(ch) { return true }
        let scheme = url[url.startIndex..<colon].lowercased()
        return ["http", "https", "mailto", "tel"].contains(scheme)
    }

    private static func firstGroup(_ re: NSRegularExpression, in text: String) -> String? {
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Replace every match of `re`, building each replacement from its capture
    /// groups. Edits are applied right-to-left so earlier ranges stay valid.
    private static func replaceMatches(_ re: NSRegularExpression,
                                       in text: String,
                                       transform: ([String]) -> String) -> String {
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for m in matches.reversed() {
            var groups: [String] = []
            for g in 0..<m.numberOfRanges {
                let r = m.range(at: g)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result = (result as NSString).replacingCharacters(in: m.range(at: 0),
                                                              with: transform(groups))
        }
        return result
    }
}
