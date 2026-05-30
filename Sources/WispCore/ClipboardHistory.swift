import Foundation

/// In-memory ring of recent clipboard entries. Newest first (index 0).
///
/// Memory-only on purpose: nothing here is ever written to disk, so quitting
/// Wisp — or restarting your Mac — leaves no trace of what you copied.
@MainActor
final class ClipboardHistory {
    private(set) var items: [ClipboardItem] = []
    private(set) var capacity: Int

    init(capacity: Int = Settings.defaultHistorySize) {
        self.capacity = max(1, capacity)
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    subscript(_ index: Int) -> ClipboardItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// Insert a new entry at the front. Existing copies of the same text are
    /// promoted to the front rather than duplicated. Equality is by text only
    /// (see `ClipboardItem`), so re-inserting *replaces* the prior entry — the
    /// newest copy's captured HTML/source wins. Tests pin this behavior.
    func insert(_ item: ClipboardItem) {
        items.removeAll { $0 == item }
        items.insert(item, at: 0)
        trim()
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    func clear() {
        items.removeAll()
    }

    func setCapacity(_ newValue: Int) {
        capacity = max(1, newValue)
        trim()
    }

    private func trim() {
        if items.count > capacity {
            items.removeLast(items.count - capacity)
        }
    }
}
