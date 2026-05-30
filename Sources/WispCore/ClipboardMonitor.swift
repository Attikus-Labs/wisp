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

        // Respect privacy markers: passwords & transient data never get recorded.
        guard !PrivacyFilter.shouldIgnore(pasteboard) else { return }

        guard let text = pasteboard.string(forType: .string) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        history.insert(ClipboardItem(text: text, sourceBundleID: PrivacyFilter.source(of: pasteboard)))
        onRecord?()
    }
}
