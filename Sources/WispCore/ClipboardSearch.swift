import Foundation

/// Pure, testable search over the in-memory clipboard history. Memory-only like
/// everything else: this only ever reads the entries already held by
/// `ClipboardHistory` — it builds no on-disk index and keeps no state. The history
/// is complete (secrets included — see `PrivacyFilter` and docs/SECURITY.md), so
/// search spans everything in RAM; nothing is indexed or written to disk.
///
/// Matching is **substring + word-aware, multi-term**, tuned for precision rather
/// than cleverness — a clipboard search should find the clip you actually
/// remember, not everything that happens to share a few letters. The query is
/// split on whitespace into terms; a clip matches only when **every** term occurs
/// in it as a case-insensitive substring (so `google cli` finds clips containing
/// both words, in any order). Ranking favours matches at word boundaries, near
/// the start of the clip, and — for multi-word queries — the whole query appearing
/// as one contiguous run; recency breaks ties. The matched character offsets come
/// back with each hit so the UI can highlight exactly what matched.
enum ClipboardSearch {
    /// One ranked hit: the entry, its original history position (0 = newest, used
    /// as the recency tiebreak), the match score, and the character offsets in
    /// `item.text` that the query matched (for highlighting).
    struct Result: Equatable {
        let item: ClipboardItem
        let index: Int
        let score: Int
        let matchedOffsets: [Int]
    }

    /// Only the first this-many characters of each clip are searched. Clipboard
    /// entries are almost always short; capping keeps filtering effectively free
    /// even with a full history of large pastes, and the preview shows the start
    /// of a clip anyway. A match deeper than this in a giant clip won't be found.
    static let maxSearchableChars = 4_000

    // Scoring weights.
    private static let scoreTerm = 20       // base, per matched term
    private static let scoreWordStart = 14  // term lands on a word boundary
    private static let scoreWholeQuery = 40 // the full multi-word query is contiguous
    private static let penaltyLeading = 1   // prefer matches nearer the clip's start

    /// Rank `items` (history order, index 0 = newest) against `query`. An empty or
    /// whitespace-only query returns every entry in history order (so search mode
    /// opens as a browsable list before you type a thing).
    static func search(_ query: String, in items: [ClipboardItem]) -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items.enumerated().map {
                Result(item: $0.element, index: $0.offset, score: 0, matchedOffsets: [])
            }
        }

        let lowerQuery = trimmed.lowercased()
        let terms = lowerQuery
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { $0.map(String.init) }            // [[String]] — each term as per-char strings
        let wholeQuery = lowerQuery.map(String.init)

        var results: [Result] = []
        for (i, item) in items.enumerated() {
            // Per-character arrays, index-aligned, so matched offsets index straight
            // into the clip's character array (and into `previewLine`).
            let original = Array(item.text.prefix(maxSearchableChars))
            let lower = original.map { String($0).lowercased() }

            var score = 0
            var offsets: [Int] = []
            var matchedAll = true
            for term in terms {
                guard let hit = matchTerm(term, lower: lower, original: original) else {
                    matchedAll = false
                    break
                }
                score += hit.score
                offsets.append(contentsOf: hit.offsets)
            }
            guard matchedAll else { continue }

            // Reward the whole query appearing as one contiguous run. Only meaningful
            // for multi-word queries — for a single term it's already the term match.
            if terms.count > 1, firstIndex(of: wholeQuery, in: lower) != nil {
                score += scoreWholeQuery
            }

            offsets = Array(Set(offsets)).sorted()
            results.append(Result(item: item, index: i, score: score, matchedOffsets: offsets))
        }

        // Best score first; newer (lower original index) wins ties.
        results.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return results
    }

    /// Best occurrence of one term as a contiguous substring: prefer the first
    /// word-boundary occurrence (better highlight + a bonus), else the first
    /// occurrence anywhere. Returns `nil` if the term isn't present at all.
    private static func matchTerm(_ term: [String], lower: [String], original: [Character]) -> (score: Int, offsets: [Int])? {
        var first = -1
        var wordStart = -1
        var from = 0
        while let pos = firstIndex(of: term, in: lower, from: from) {
            if first < 0 { first = pos }
            if isWordStart(original, at: pos) { wordStart = pos; break }
            from = pos + 1
        }
        let pos = wordStart >= 0 ? wordStart : first
        guard pos >= 0 else { return nil }

        var score = scoreTerm + term.count          // longer, more specific terms score higher
        if wordStart >= 0 { score += scoreWordStart }
        score -= min(pos, 40) * penaltyLeading
        return (score, Array(pos..<(pos + term.count)))
    }

    /// Index of the first contiguous occurrence of `needle` within `hay` at or
    /// after `from`, comparing element-wise (each element is one lowercased char).
    private static func firstIndex(of needle: [String], in hay: [String], from: Int = 0) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        let last = hay.count - needle.count
        var j = max(from, 0)
        while j <= last {
            var k = 0
            while k < needle.count, hay[j + k] == needle[k] { k += 1 }
            if k == needle.count { return j }
            j += 1
        }
        return nil
    }

    /// A character begins a "word" if it's at the start, follows a separator, or is
    /// an uppercase letter after a lowercase one (camelCase). Used to reward
    /// matches that land on word boundaries.
    private static func isWordStart(_ chars: [Character], at i: Int) -> Bool {
        guard i > 0 else { return true }
        let p = chars[i - 1]
        if p == " " || p == "\n" || p == "\t" || p == "/" || p == "_" || p == "-"
            || p == "." || p == ":" || p == "(" || p == "[" || p == "{" || p == "," {
            return true
        }
        return p.isLowercase && chars[i].isUppercase
    }

    /// How much of one line is returned as a snippet. A "line" in a clipboard clip
    /// can be the entire clip — minified JSON, a base64 blob, a single-line log — and
    /// the row that shows it is about sixty characters wide, so reading further buys
    /// the user nothing.
    static let maxPreviewLineChars = 500

    /// The single line of `text` containing `offset`, with leading whitespace
    /// trimmed for display, plus the character index in `text` where that returned
    /// line begins. The view subtracts `start` from each matched offset to place
    /// highlights within the snippet. With no match, pass `offset == 0` to get the
    /// first line.
    ///
    /// Walks by `String.Index` rather than materialising `Array(text)`: this runs once
    /// per result on every keystroke, and turning a 2 MB clip into a `[Character]`
    /// costs ~10ms — over two seconds across a full 200-entry history. Every walk here
    /// is bounded: backwards by `offset` (which never exceeds `maxSearchableChars`),
    /// forwards by `maxPreviewLineChars`.
    static func previewLine(for text: String, around offset: Int) -> (line: String, start: Int) {
        guard !text.isEmpty else { return ("", 0) }

        // The character at `offset`, clamped into the string.
        let position = text.index(text.startIndex, offsetBy: max(offset, 0),
                                  limitedBy: text.endIndex).flatMap {
            $0 == text.endIndex ? text.index(before: text.endIndex) : $0
        } ?? text.index(before: text.endIndex)

        // Back up to the start of the line. "\r\n" is a single Character, so it has to
        // be matched in its own right or a CRLF clip reads as one enormous line.
        var lineStart = position
        while lineStart > text.startIndex {
            let previous = text.index(before: lineStart)
            if isLineBreak(text[previous]) { break }
            lineStart = previous
        }

        // Leading indentation is dropped for display; it stops at the line's end
        // because a newline is neither a space nor a tab.
        var start = lineStart
        while start < text.endIndex, text[start] == " " || text[start] == "\t" {
            start = text.index(after: start)
        }

        var end = start
        var length = 0
        while end < text.endIndex, length < maxPreviewLineChars, !isLineBreak(text[end]) {
            end = text.index(after: end)
            length += 1
        }
        return (String(text[start..<end]), text.distance(from: text.startIndex, to: start))
    }

    private static func isLineBreak(_ c: Character) -> Bool {
        c == "\n" || c == "\r" || c == "\r\n"
    }
}
