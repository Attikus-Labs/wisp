import Foundation

/// One remembered clipboard entry. The canonical content is always plain text
/// (like Flycut) — no images or files are ever retained. When the source app
/// also offers HTML, it is held *in memory* too, so a formatted paste (⌥⏎) can
/// reproduce the original formatting faithfully. That HTML is never written to
/// disk and never leaves the Mac. Everything here lives only in memory.
struct ClipboardItem: Equatable {
    let text: String
    /// The source's rich HTML, captured at copy time when the source app provides
    /// it. `nil` for plain copies, or when that HTML is blank or over the per-clip
    /// size budget.
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
