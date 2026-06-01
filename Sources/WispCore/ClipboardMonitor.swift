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

        // The originating app: prefer the advertised nspasteboard source marker,
        // else the frontmost app at copy time — how a clip's origin is usually known,
        // since few apps set the marker. Used both to label the entry and to widen
        // the privacy net.
        let source = PrivacyFilter.source(of: pasteboard)
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Respect privacy markers, and skip known-secret source apps even when they
        // set no marker (belt-and-suspenders for password managers). Checking the
        // frontmost app here is what stops a marker-less password manager's copy from
        // being both recorded AND labelled with its name.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !PrivacyFilter.shouldIgnore(types: types, source: source) else { return }

        guard let text = pasteboard.string(forType: .string) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Per-clip memory budget — the user's chosen ceiling on what Wisp will retain
        // (0 == unlimited). The plain text is the canonical content, so a clip whose
        // text alone blows the budget isn't recorded at all: it stays on the system
        // pasteboard (a manual ⌘V still works), Wisp just won't remember it. Raising
        // the cap in the menu is how you opt into keeping large pastes.
        let cap = Settings.maxClipBytes
        if cap != Settings.unlimitedClipBytes, text.utf8.count > cap { return }

        // Keep the source's rich HTML in memory (for ⌥⏎ formatted paste). Only reached
        // for non-ignored items, so passwords/transient copies are already excluded by
        // the privacy filter above. Skip blank HTML (would paste as an empty rich
        // flavor) and hold it to the same per-clip budget — HTML over the cap is
        // dropped, the entry stays plain text, and ⌥⏎ falls back to Markdown synthesis,
        // so one giant rich clip can't bloat RAM.
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
