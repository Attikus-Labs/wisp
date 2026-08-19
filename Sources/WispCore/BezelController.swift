import AppKit
import Carbon.HIToolbox

/// Drives the bezel: shows it on the hot key, lets ← / → walk the history, and
/// pastes the chosen entry into the app you came from. Pressing `/` drops the
/// carousel into a live search-the-history list (see `SearchView`); the same
/// ⏎ / ⌥⏎ / ⇧⏎ keys paste the highlighted result, and ⎋ steps back out.
///
/// Interaction model is faithful to Flycut/Jumpcut: the bezel takes focus while
/// it's up, then hands focus back to the previous app when you paste.
@MainActor
final class BezelController: NSObject, NSWindowDelegate {
    private let history: ClipboardHistory
    private let view = BezelView()
    private lazy var searchView: SearchView = {
        let view = SearchView()
        view.onQueryChange = { [weak self] _ in self?.updateResults() }
        view.onActivate = { [weak self] in self?.pasteSelected(mode: .plain) }
        return view
    }()
    private lazy var panel: BezelPanel = {
        let panel = BezelPanel(contentView: view)
        panel.onKey = { [weak self] key in self?.handle(key) }
        panel.delegate = self
        return panel
    }()

    /// Browse = the single-clip carousel; search = the filtered list.
    private enum Mode { case browse, search }
    private var mode: Mode = .browse
    /// Active only in search mode: intercepts ↑↓ / ⏎ / ⎋ before the query field's
    /// editor sees them, while letting it edit text normally.
    private var searchMonitor: Any?
    /// The current ranked results, parallel to the rows shown in `searchView`.
    private var results: [ClipboardSearch.Result] = []

    private var index = 0
    private var previousApp: NSRunningApplication?
    private var isShowing = false
    /// True while the bezel is up purely as a live style preview (from the settings
    /// menu) rather than a real, focus-stealing invocation. Torn down by `endPreview`.
    private var isPreview = false

    /// The currently shown HUD card (carousel or search), for live restyling.
    private var styledView: BezelEffectView? { panel.contentView as? BezelEffectView }

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
        isPreview = false
        mode = .browse
        panel.contentView = view
        view.applyStyle() // pick up any appearance/transparency change from the menu
        render()
        position(preferredSize: BezelView.size)
        // No NSApp.activate: the nonactivating panel takes key focus on its own (so
        // Tab/arrows/⏎ work immediately) without stealing the target app's activation,
        // so the form you're pasting into keeps its focus. Paster re-targets it on paste.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil) // keys flow to the panel for carousel handling
        isShowing = true
    }

    // MARK: - Live style preview (driven by the settings menu)

    /// Reflect an appearance/transparency change on screen *as the user drags the
    /// slider*. If the bezel is already up, restyle it in place; otherwise pop it up
    /// as a preview that doesn't steal focus — `orderFront`, not `makeKey`/`activate`
    /// — so the open menu the slider lives in stays open. `endPreview()` removes it.
    func previewStyle() {
        if isShowing {
            styledView?.applyStyle()
            return
        }
        if !isPreview {
            mode = .browse
            panel.contentView = view
            let item = history[0] ?? ClipboardItem(text: "Bezel transparency preview")
            view.update(item: item, index: 0, count: max(history.count, 1))
            position(preferredSize: BezelView.size)
            panel.orderFront(nil) // visible without becoming key, so the menu survives
            isPreview = true
        }
        view.applyStyle()
    }

    /// Tear down a style preview (called when the settings menu closes). No-op if the
    /// bezel is up for real.
    func endPreview() {
        guard isPreview else { return }
        isPreview = false
        panel.orderOut(nil)
    }

    func hide() {
        isShowing = false
        isPreview = false
        if mode == .search {
            removeSearchMonitor()
            mode = .browse
        }
        panel.orderOut(nil)
    }

    // MARK: - Key handling (carousel)

    private func handle(_ key: BezelKey) {
        switch key {
        case .older:       move(by: +1)
        case .newer:       move(by: -1)
        case .paste:       pasteCurrent(mode: .plain)
        case .pasteRich:   pasteCurrent(mode: .rich)
        case .pasteReflow: pasteCurrent(mode: .reflow)
        case .dismiss:     hide()
        case .delete:      deleteCurrent()
        case .search:      enterSearch()
        // Reading a clip taller than the card: it scrolls, the card doesn't grow.
        case .scrollUp:       scrollPreview(lines: -3)
        case .scrollDown:     scrollPreview(lines: +3)
        case .scrollPageUp:   scrollPreview(pages: -1)
        case .scrollPageDown: scrollPreview(pages: +1)
        case .scrollToStart:  scrollPreviewToEdge(start: true)
        case .scrollToEnd:    scrollPreviewToEdge(start: false)
        }
    }

    // Scrolling applies to whichever card is up: the carousel's preview or the
    // search HUD's detail pane.

    private func scrollPreview(lines: Int) {
        switch mode {
        case .browse: view.scrollPreview(lines: lines)
        case .search: searchView.scrollPreview(lines: lines)
        }
    }

    private func scrollPreview(pages: Int) {
        switch mode {
        case .browse: view.scrollPreview(pages: pages)
        case .search: searchView.scrollPreview(pages: pages)
        }
    }

    private func scrollPreviewToEdge(start: Bool) {
        switch mode {
        case .browse: view.scrollPreviewToEdge(start: start)
        case .search: searchView.scrollPreviewToEdge(start: start)
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

    /// How ⏎ / ⌥⏎ / ⇧⏎ deliver an entry. The stored item is never mutated — only
    /// the outgoing paste is transformed.
    private enum PasteMode { case plain, rich, reflow }

    private func pasteCurrent(mode: PasteMode = .plain) {
        guard let item = history[index] else { hide(); return }
        hide()
        performPaste(item: item, mode: mode)
        // Promote what we just used so it's the most-recent next time.
        history.insert(item)
    }

    /// Shared by the carousel and the search list: place `item` on the pasteboard
    /// in the requested mode and deliver it to the previous app.
    private func performPaste(item: ClipboardItem, mode: PasteMode) {
        switch mode {
        case .plain:
            Paster.paste(item.text, into: previousApp)
        case .rich:
            // Prefer the source's own formatting when we captured it; otherwise
            // synthesize from the entry's Markdown.
            Paster.pasteFormatted(text: item.text, sourceHTML: item.html, into: previousApp)
        case .reflow:
            // Terminal output has no source HTML — reflow the text and synthesize.
            Paster.pasteFormatted(text: TerminalText.reflow(item.text), sourceHTML: nil, into: previousApp)
        }
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

    /// Place the panel, clamping the card to the screen it lands on. `preferredSize`
    /// is what the card asks for; a small display gets a smaller card (its preview
    /// scrolls) rather than a card hanging off the bottom of the screen.
    private func position(preferredSize: NSSize) {
        let screens = NSScreen.screens.map {
            BezelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        // Anchor on the screen under the mouse pointer — where the user's attention
        // is. Deliberately not `NSScreen.main`, which for a non-activating accessory
        // panel resolves to the wrong display across Sidecar / multi-monitor /
        // per-display Spaces (the bug this fixes). Which *Space* the bezel lands on
        // is orthogonal to geometry — that's the panel's `.canJoinAllSpaces` job.
        guard let frame = BezelPlacement.frame(preferredSize: preferredSize,
                                               anchor: NSEvent.mouseLocation,
                                               screens: screens) else { return }
        panel.setFrame(frame, display: true)
    }

    // MARK: - Search mode

    /// Swap the carousel for the search list, focus the query field, and start
    /// intercepting navigation keys. Entered by `/` from the carousel.
    private func enterSearch() {
        guard isShowing, mode == .browse else { return }
        mode = .search
        searchView.clearQuery()
        panel.contentView = searchView
        searchView.applyStyle() // match the carousel's appearance/transparency
        position(preferredSize: SearchView.size)
        searchView.focusQueryField()
        installSearchMonitor()
        updateResults()
    }

    /// Return to the carousel (⎋ on an empty query). The history is unchanged, so
    /// we land on the most-recent clip.
    private func exitSearch() {
        guard mode == .search else { return }
        removeSearchMonitor()
        mode = .browse
        index = 0
        panel.contentView = view
        render()
        position(preferredSize: BezelView.size)
        panel.makeFirstResponder(nil) // hand keys back to the panel
    }

    /// Re-run the filter and refresh the list. Cheap: ≤80 short in-memory strings.
    private func updateResults() {
        guard mode == .search else { return }
        results = ClipboardSearch.search(searchView.query, in: history.items)
        searchView.show(rows: results.map(makeRow))
    }

    private func pasteSelected(mode: PasteMode) {
        guard let item = searchView.selectedItem else { return }
        hide()
        performPaste(item: item, mode: mode)
        history.insert(item)
    }

    /// Turn a ranked result into a displayable row: a one-line snippet centred on
    /// the first match, with the matched characters emphasised, plus the source app.
    /// The row's line count is added by the view for the rows actually on screen
    /// (see `SearchView.Row`) — a row is one line by construction, so without that
    /// count a 200-line clip and a one-liner look identical in the list.
    private func makeRow(_ result: ClipboardSearch.Result) -> SearchView.Row {
        let offset = result.matchedOffsets.first ?? 0
        let (line, start) = ClipboardSearch.previewLine(for: result.item.text, around: offset)
        let snippet = highlightedSnippet(line: line, lineStart: start, matched: result.matchedOffsets)
        let source = AppDisplayName.resolve(result.item.sourceBundleID) ?? ""
        return SearchView.Row(item: result.item, snippet: snippet, source: source,
                              matchedOffsets: result.matchedOffsets)
    }

    private func highlightedSnippet(line: String, lineStart: Int, matched: [Int]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: line, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ])
        guard !line.isEmpty, !matched.isEmpty else { return attributed }
        let highlight: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor,
        ]
        let count = line.count
        for offset in matched {
            let position = offset - lineStart
            guard position >= 0, position < count else { continue }
            let lower = line.index(line.startIndex, offsetBy: position)
            let upper = line.index(after: lower)
            attributed.addAttributes(highlight, range: NSRange(lower..<upper, in: line))
        }
        return attributed
    }

    // MARK: - Search key monitor

    /// A local key monitor fires before the query field's editor, so we can claim
    /// ↑↓ (and ⌃P/⌃N), the three ⏎ paste variants, and ⎋ — returning `nil` to
    /// swallow them — while every other key (text, ⌫, ⌘A/C/V, caret motion) flows
    /// through to the field for normal editing.
    private func installSearchMonitor() {
        guard searchMonitor == nil else { return }
        searchMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.mode == .search else { return event }
            return self.handleSearchKey(event) ? nil : event
        }
    }

    private func removeSearchMonitor() {
        if let monitor = searchMonitor { NSEvent.removeMonitor(monitor) }
        searchMonitor = nil
    }

    /// Returns true if the key was a search command (and should be swallowed).
    private func handleSearchKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags
        let control = mods.contains(.control)
        let code = Int(event.keyCode)

        // ⌥↑/⌥↓ scroll the preview pane and ⌘↑/⌘↓ jump to its ends, rather than moving
        // the selection — the pane is where a long clip is read, and these are the
        // same bindings as the carousel. Claimed before the plain arrows below, which
        // match on key code alone. (⌘←/→ and ⇱/⇲ are left to the query field, where
        // they're real editing keys; on a single-line field ⌘↑/⌘↓ only duplicate them.)
        if code == kVK_UpArrow || code == kVK_DownArrow {
            let up = code == kVK_UpArrow
            if mods.contains(.option) {
                searchView.scrollPreview(lines: up ? -3 : +3)
                return true
            }
            if mods.contains(.command) {
                searchView.scrollPreviewToEdge(start: up)
                return true
            }
        }
        switch code {
        case kVK_PageUp:
            searchView.scrollPreview(pages: -1)
            return true
        case kVK_PageDown:
            searchView.scrollPreview(pages: +1)
            return true
        case kVK_UpArrow:
            searchView.moveSelection(by: -1)
            return true
        case kVK_DownArrow:
            searchView.moveSelection(by: +1)
            return true
        case kVK_ANSI_P where control: // vi/emacs-style previous
            searchView.moveSelection(by: -1)
            return true
        case kVK_ANSI_N where control: // vi/emacs-style next
            searchView.moveSelection(by: +1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if mods.contains(.shift) {
                pasteSelected(mode: .reflow)
            } else if mods.contains(.option) {
                pasteSelected(mode: .rich)
            } else {
                pasteSelected(mode: .plain)
            }
            return true
        case kVK_Escape:
            // First ⎋ clears a non-empty query; an empty query returns to the carousel.
            if searchView.query.isEmpty {
                exitSearch()
            } else {
                searchView.clearQuery()
                updateResults()
            }
            return true
        default:
            return false
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Clicking away (or switching apps) dismisses the bezel.
        if isShowing { hide() }
    }
}
