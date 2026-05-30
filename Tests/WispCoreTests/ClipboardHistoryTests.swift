import Testing
@testable import WispCore

@MainActor
struct ClipboardHistoryTests {
    @Test func newestFirst() {
        let history = ClipboardHistory(capacity: 5)
        history.insert(ClipboardItem(text: "a"))
        history.insert(ClipboardItem(text: "b"))
        #expect(history.items.map(\.text) == ["b", "a"])
    }

    @Test func reinsertingPromotesInsteadOfDuplicating() {
        let history = ClipboardHistory(capacity: 5)
        history.insert(ClipboardItem(text: "a"))
        history.insert(ClipboardItem(text: "b"))
        history.insert(ClipboardItem(text: "a"))
        #expect(history.items.map(\.text) == ["a", "b"])
        #expect(history.count == 2)
    }

    @Test func capacityTrimsOldest() {
        let history = ClipboardHistory(capacity: 3)
        for text in ["a", "b", "c", "d", "e"] {
            history.insert(ClipboardItem(text: text))
        }
        #expect(history.items.map(\.text) == ["e", "d", "c"])
    }

    @Test func shrinkingCapacityTrims() {
        let history = ClipboardHistory(capacity: 5)
        for text in ["a", "b", "c", "d", "e"] {
            history.insert(ClipboardItem(text: text))
        }
        history.setCapacity(2)
        #expect(history.items.map(\.text) == ["e", "d"])
    }

    @Test func removeAtIndex() {
        let history = ClipboardHistory(capacity: 5)
        for text in ["a", "b", "c"] {
            history.insert(ClipboardItem(text: text))
        }
        // items are newest-first: ["c", "b", "a"] — remove "b".
        history.remove(at: 1)
        #expect(history.items.map(\.text) == ["c", "a"])
    }

    @Test func subscriptBounds() {
        let history = ClipboardHistory(capacity: 5)
        history.insert(ClipboardItem(text: "only"))
        #expect(history[0]?.text == "only")
        #expect(history[1] == nil)
        #expect(history[-1] == nil)
    }
}
