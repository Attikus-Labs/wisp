import Foundation

/// One remembered clipboard entry. The canonical content is always plain text
/// (like Flycut) — no images or files are ever retained. Optionally, when "Keep
/// Source Formatting" is on, the source app's own HTML is held *in memory* too, so
/// a formatted paste (⌥⏎) can reproduce the original formatting faithfully. That
/// HTML is never written to disk and never leaves the Mac; it is opt-out via the
/// menu. Everything here lives only in memory.
struct ClipboardItem: Equatable {
    let text: String
    /// The source's rich HTML, captured at copy time when present and allowed.
    /// `nil` for plain copies or when formatting capture is disabled.
    let html: String?
    let sourceBundleID: String?

    init(text: String, html: String? = nil, sourceBundleID: String? = nil) {
        self.text = text
        self.html = html
        self.sourceBundleID = sourceBundleID
    }

    /// Two entries are "the same" when their text matches, so re-copying
    /// promotes rather than duplicates (the newer copy's HTML wins on reinsert).
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.text == rhs.text
    }
}
