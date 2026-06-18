import AppKit
import Testing
@testable import WispCore

/// Drives the monitor's poll directly against a private, uniquely named
/// pasteboard — no run loop, no touching the user's real clipboard.
@MainActor
struct ClipboardMonitorTests {
    private func makeMonitor() -> (NSPasteboard, ClipboardHistory, ClipboardMonitor) {
        let pb = NSPasteboard.withUniqueName()
        let history = ClipboardHistory(capacity: 10)
        let monitor = ClipboardMonitor(history: history, pasteboard: pb)
        return (pb, history, monitor)
    }

    @Test func recordsAPlainCopy() {
        let (pb, history, monitor) = makeMonitor()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        #expect(pb.setString("hello", forType: .string))
        monitor.poll()
        #expect(history.items.map(\.text) == ["hello"])
    }

    /// The swallowed-clip bug: a poll landing in another app's clear-to-write
    /// gap (see poll()'s two-phase-write note) must not consume the generation —
    /// the next tick has to pick the text up.
    @Test func pollInsideClearToWriteGapDoesNotSwallowTheClip() {
        let (pb, history, monitor) = makeMonitor()
        defer { pb.releaseGlobally() }

        pb.clearContents() // phase 1: changeCount bumps, no text yet
        monitor.poll()     // tick lands in the gap
        #expect(history.isEmpty)

        #expect(pb.setString("late text", forType: .string)) // phase 2: no further bump
        monitor.poll() // next tick must still see this generation
        #expect(history.items.map(\.text) == ["late text"])
    }

    /// A generation that never produces text (image-only copy, cleared board)
    /// is given up after the gap budget — not re-read every tick forever.
    /// Pinned observably: text arriving after the give-up is NOT recorded,
    /// because the generation was consumed.
    @Test func textlessGenerationIsGivenUpAfterBoundedRetries() {
        let (pb, history, monitor) = makeMonitor()
        defer { pb.releaseGlobally() }

        pb.clearContents() // a clip with no string flavor, e.g. an image
        monitor.poll()
        monitor.poll()
        monitor.poll() // past the budget — generation consumed
        #expect(pb.setString("far too late", forType: .string)) // same generation
        monitor.poll()
        #expect(history.isEmpty)
    }

    /// A clobbered-to-empty board (e.g. a terminal copying an empty selection)
    /// is settled, not a gap: skipped immediately, never recorded, and the next
    /// real copy records normally.
    @Test func emptyClipIsSkippedAndNextRealCopyStillRecords() {
        let (pb, history, monitor) = makeMonitor()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        #expect(pb.setString("", forType: .string))
        monitor.poll()
        #expect(history.isEmpty)

        pb.clearContents()
        #expect(pb.setString("real copy", forType: .string))
        monitor.poll()
        #expect(history.items.map(\.text) == ["real copy"])
    }

    /// Wisp's own paste echo is a deliberate skip, and a following external
    /// copy records normally. (Why the echo is skipped at all is pinned in
    /// PrivacyFilterTests.)
    @Test func selfPasteEchoIsSkipped() {
        let (pb, history, monitor) = makeMonitor()
        defer { pb.releaseGlobally() }

        pb.clearContents()
        #expect(pb.setString("", forType: PrivacyFilter.selfPasteType))
        #expect(pb.setString("pasted by wisp", forType: .string))
        monitor.poll()
        #expect(history.isEmpty)

        pb.clearContents()
        #expect(pb.setString("external copy", forType: .string))
        monitor.poll()
        #expect(history.items.map(\.text) == ["external copy"])
    }
}
