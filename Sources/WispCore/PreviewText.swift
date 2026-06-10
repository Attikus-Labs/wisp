import Foundation

/// Shared shaping for what the bezel and search preview labels display. The
/// labels wrap with no line cap (the container edge is the cap — see
/// `BezelEffectView.wrappingPreviewLabel`), so the text fed to them is bounded
/// here instead. The full clip text is always what gets pasted.
enum PreviewText {
    /// More characters than either preview can ever lay out — the roomiest case
    /// is search's preview over a one-row list, ~75 chars × ~22 lines, and this
    /// leaves generous headroom. Capping the *label text* keeps a megabyte clip
    /// from making an uncapped label measure the whole thing; content that could
    /// never be visible is all it drops.
    static let displayCap = 4096

    /// Drop leading blank lines and trailing whitespace (both only waste preview
    /// height), keep leading spaces on the first kept line (revealed against the
    /// container's inset edge), and cap the result at `displayCap`.
    ///
    /// Order matters twice over:
    ///   • blank lines are dropped BEFORE capping, so a clip that starts with
    ///     thousands of them still previews its content rather than nothing;
    ///   • when the cap does cut content short, trailing whitespace is kept, so
    ///     the label still overflows and the last-visible-line ellipsis keeps
    ///     signalling "there's more" even if what follows the cut is blank.
    static func trimmed(_ text: String) -> String {
        var s = Substring(text)
        while let f = s.first, f.isNewline { s = s.dropFirst() }
        if let cut = s.index(s.startIndex, offsetBy: displayCap, limitedBy: s.endIndex),
           cut < s.endIndex {
            return String(s[..<cut])
        }
        while let l = s.last, l.isWhitespace { s = s.dropLast() }
        return String(s)
    }
}
