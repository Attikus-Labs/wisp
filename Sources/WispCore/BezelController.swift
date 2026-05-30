import AppKit

/// Drives the bezel: shows it on the hot key, lets ← / → walk the history, and
/// pastes the chosen entry into the app you came from.
///
/// Interaction model is faithful to Flycut/Jumpcut: the bezel takes focus while
/// it's up, then hands focus back to the previous app when you paste.
@MainActor
final class BezelController: NSObject, NSWindowDelegate {
    private let history: ClipboardHistory
    private let view = BezelView()
    private lazy var panel: BezelPanel = {
        let panel = BezelPanel(contentView: view)
        panel.onKey = { [weak self] key in self?.handle(key) }
        panel.delegate = self
        return panel
    }()

    private var index = 0
    private var previousApp: NSRunningApplication?
    private var isShowing = false

    init(history: ClipboardHistory) {
        self.history = history
        super.init()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !history.isEmpty else {
            NSSound.beep()
            return
        }
        index = 0
        previousApp = NSWorkspace.shared.frontmostApplication
        render()
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isShowing = true
    }

    func hide() {
        isShowing = false
        panel.orderOut(nil)
    }

    // MARK: - Key handling

    private func handle(_ key: BezelKey) {
        switch key {
        case .older:   move(by: +1)
        case .newer:   move(by: -1)
        case .paste:   pasteCurrent()
        case .dismiss: hide()
        case .delete:  deleteCurrent()
        }
    }

    private func move(by delta: Int) {
        guard !history.isEmpty else { return }
        // Wrap around the ends so navigation loops through the whole history
        // instead of stopping at the newest / oldest entry.
        let count = history.count
        index = ((index + delta) % count + count) % count
        render()
    }

    private func pasteCurrent() {
        guard let item = history[index] else { hide(); return }
        hide()
        Paster.paste(item.text, into: previousApp)
        // Promote what we just used so it's the most-recent next time.
        history.insert(item)
    }

    private func deleteCurrent() {
        guard !history.isEmpty else { return }
        history.remove(at: index)
        if history.isEmpty { hide(); return }
        index = min(index, history.count - 1)
        render()
    }

    private func render() {
        guard let item = history[index] else { hide(); return }
        view.update(item: item, index: index, count: history.count)
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = BezelView.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + visible.height * 0.08
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking away (or switching apps) dismisses the bezel.
        if isShowing { hide() }
    }
}
