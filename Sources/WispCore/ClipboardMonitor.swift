import AppKit

/// Polls the system pasteboard for changes. macOS has no "clipboard changed"
/// notification, so — like every clipboard manager — Wisp watches `changeCount`
/// on a light timer. At 0.5s with tolerance this is effectively free.
@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let history: ClipboardHistory

    /// Called after a new entry is recorded (lets the UI refresh if needed).
    var onRecord: (() -> Void)?

    init(history: ClipboardHistory) {
        self.history = history
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

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // The originating app, purely for labelling the entry: prefer the advertised
        // nspasteboard source marker, else the frontmost app at copy time — how a
        // clip's origin is usually known, since few apps set the marker.
        let source = PrivacyFilter.source(of: pasteboard)
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Wisp records everything you copy (secrets included — see PrivacyFilter and
        // docs/SECURITY.md). The only thing skipped here is Wisp's *own* paste echo,
        // which carries our private self-paste marker; re-recording it would clobber
        // the entry's captured HTML with a text-only copy.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !PrivacyFilter.shouldIgnore(types: types) else { return }

        guard let text = pasteboard.string(forType: .string) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

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
