import AppKit

/// Polls the system pasteboard for changes. macOS has no "clipboard changed"
/// notification, so — like every clipboard manager — Wisp watches `changeCount`
/// on a light timer. At 0.5s with tolerance this is effectively free.
@MainActor
final class ClipboardMonitor {
    /// Upper bound on retained source HTML per entry — keeps a pathological
    /// multi-megabyte clipping from bloating the in-memory history. Past this, the
    /// entry stays plain text and ⌥⏎ falls back to Markdown synthesis.
    private static let maxCapturedHTMLBytes = 2_000_000

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

        // Optionally keep the source's rich HTML in memory (for ⌥⏎ formatted paste).
        // Only reached for non-ignored items, so passwords/transient copies are
        // already excluded by the privacy filter above. Skip blank HTML (would
        // paste as an empty rich flavor) and bound the size we retain.
        var html: String?
        if Settings.keepFormatting,
           let h = pasteboard.string(forType: .html),
           !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           h.utf8.count <= Self.maxCapturedHTMLBytes {
            html = h
        }

        history.insert(ClipboardItem(text: text, html: html, sourceBundleID: source))
        onRecord?()
    }
}
