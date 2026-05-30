import Foundation

/// One remembered clipboard entry. Text-only by design (like Flycut): Wisp never
/// retains images, files, or rich data — smaller footprint, smaller attack
/// surface. Lives only in memory.
struct ClipboardItem: Equatable {
    let text: String
    let sourceBundleID: String?

    init(text: String, sourceBundleID: String? = nil) {
        self.text = text
        self.sourceBundleID = sourceBundleID
    }

    /// Two entries are "the same" when their text matches, so re-copying
    /// promotes rather than duplicates.
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.text == rhs.text
    }
}
