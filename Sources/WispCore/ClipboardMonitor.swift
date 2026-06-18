import AppKit

/// Polls the system pasteboard for changes. macOS has no "clipboard changed"
/// notification, so — like every clipboard manager — Wisp watches `changeCount`
/// on a light timer. At 0.5s with tolerance this is effectively free.
@MainActor
final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let history: ClipboardHistory

    // Generation-in-flight bookkeeping for two-phase writes (see poll()).
    // A clipboard "generation" is one changeCount value: clearContents() bumps
    // it, the setString()/setData() calls that follow do NOT. These remember a
    // generation we've seen but couldn't read text from yet, how many ticks
    // we've waited on it, and who was frontmost when it appeared.
    private var pendingGeneration: Int?
    private var pendingTicks = 0
    private var pendingSource: String?

    /// How many ticks a text-less generation is re-read before being written
    /// off as a non-text clip (image, file, cleared board). The real
    /// clear-to-write gap is microseconds, so one tick is already generous —
    /// two keeps a slow writer covered without re-reading a screenshot's
    /// generation every 0.5s for hours.
    private static let maxGapTicks = 2

    /// Called after a new entry is recorded (lets the UI refresh if needed).
    var onRecord: (() -> Void)?

    init(history: ClipboardHistory, pasteboard: NSPasteboard = .general) {
        self.history = history
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval = 0.5) {
        stop()
        // Target/selector timer fires on the main run loop — no actor hop needed.
        let timer = Timer(timeInterval: interval, target: self,
                          selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.25 // let macOS coalesce wake-ups; battery-friendly
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func tick() {
        poll()
    }

    // Internal (not private) so tests can drive a poll directly against an
    // injected pasteboard instead of spinning the run loop.
    func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }

        // First look at this generation: note the frontmost app NOW, so a clip
        // whose text only materializes on a later tick (see the gap handling
        // below) is still labelled with the app the user copied from, not
        // whatever they switched to since.
        if current != pendingGeneration {
            pendingGeneration = current
            pendingTicks = 0
            pendingSource = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }

        // Wisp records everything you copy (secrets included — see PrivacyFilter and
        // docs/SECURITY.md). The only thing skipped here is Wisp's *own* paste echo,
        // which carries our private self-paste marker; re-recording it would clobber
        // the entry's captured HTML with a text-only copy.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        if PrivacyFilter.shouldIgnore(types: types) {
            lastChangeCount = current
            return
        }

        // Two-phase writes: another app's clearContents() bumps changeCount, but the
        // setString() that follows does NOT bump it again. A poll landing in that gap
        // sees no string at all — consuming the generation here would miss the clip
        // forever (no further bump ever comes), so wait a tick or two for the text.
        // Past the budget it's not a gap, it's a text-less clip (image, file, cleared
        // board): give up so we don't re-read that generation until the next copy.
        guard let text = pasteboard.string(forType: .string) else {
            pendingTicks += 1
            if pendingTicks >= Self.maxGapTicks { lastChangeCount = current }
            return
        }
        // A present-but-blank string is treated as settled, not as a gap. The owner
        // *can* still replace it within the same generation (setString again, no
        // changeCount bump) — but that's invisible to any changeCount poller, so
        // waiting wouldn't help; we'd just re-read the blank forever or record it.
        // Consume, and skip recording the blank.
        lastChangeCount = current
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // The originating app, purely for labelling the entry: prefer the advertised
        // nspasteboard source marker, else the frontmost app at copy time (sampled
        // when this generation first appeared) — how a clip's origin is usually
        // known, since few apps set the marker.
        let source = PrivacyFilter.source(of: pasteboard) ?? pendingSource

        // Per-clip memory budget — the user's chosen ceiling on what Wisp will retain
        // (0 == unlimited). The plain text is the canonical content, so a clip whose
        // text alone blows the budget isn't recorded at all: it stays on the system
        // pasteboard (a manual ⌘V still works), Wisp just won't remember it. Raising
        // the cap in the menu is how you opt into keeping large pastes.
        let cap = Settings.maxClipBytes
        if cap != Settings.unlimitedClipBytes, text.utf8.count > cap { return }

        // Keep the source's rich HTML in memory (for ⌥⏎ formatted paste). Like the
        // plain text, it never touches disk and never leaves the machine. Skip blank
        // HTML (would paste as an empty rich flavor) and hold it to the same per-clip
        // budget — HTML over the cap is dropped, the entry stays plain text, and ⌥⏎
        // falls back to Markdown synthesis, so one giant rich clip can't bloat RAM.
        var html: String?
        if let h = pasteboard.string(forType: .html),
           !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           cap == Settings.unlimitedClipBytes || h.utf8.count <= cap {
            html = h
        }

        history.insert(ClipboardItem(text: text, html: html, sourceBundleID: source))
        onRecord?()
    }
}
