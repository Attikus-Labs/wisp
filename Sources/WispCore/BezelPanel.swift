import AppKit
import Carbon.HIToolbox

/// A key press the bezel cares about.
enum BezelKey {
    case older       // step back into history (further from the newest)
    case newer       // step toward the most-recent copy
    case paste       // ⏎ : paste plain text
    case pasteRich   // ⌥⏎ : paste with formatting (render Markdown → rich text)
    case pasteReflow // ⇧⏎ : reflow terminal output, then paste formatted
    case dismiss     // esc
    case delete      // ⌫ : drop the current entry
    case search      // / : switch the bezel into search-the-history mode
    // Reading a clip that's taller than the card. The card never grows past the
    // screen, so these are how you see the rest of a long clip.
    case scrollUp      // ⌥↑
    case scrollDown    // ⌥↓
    case scrollPageUp  // ⇞ (fn↑)
    case scrollPageDown // ⇟ (fn↓)
    case scrollToStart // ⌘↑ / ↖ (fn←)
    case scrollToEnd   // ⌘↓ / ↘ (fn→)
}

/// Borderless floating panel that hosts the bezel. It overrides `canBecomeKey`
/// so it can receive arrow keys despite having no title bar.
@MainActor
final class BezelPanel: NSPanel {
    var onKey: ((BezelKey) -> Void)?

    init(contentView: NSView) {
        // `.nonactivatingPanel` lets the bezel become the KEY window — and receive
        // keys (arrows, ⏎, Tab) — without activating Wisp over the app you're pasting
        // into. So the bezel takes keyboard focus the instant it appears (no click
        // needed), while the target form's app stays active in the background; the
        // paste path re-targets it and sends ⌘V. Without this, an accessory app's
        // borderless panel often orders-front-but-not-key on modern macOS, so keys
        // go nowhere until you click it.
        super.init(contentRect: contentView.bounds,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.contentView = contentView
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false // become key on show, not only when a control is clicked
        level = .modalPanel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Wisp's history can contain secrets, and the bezel/search HUD render clip
        // text as plaintext. Exclude this window from screen capture so screenshots,
        // screen recordings, and screen sharing can't scrape it. (Available since
        // macOS 10.5; covers the search HUD too — BezelController reuses this panel,
        // swapping its contentView rather than opening a second window.) Does NOT
        // stop someone physically looking at the screen — see docs/SECURITY.md.
        sharingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // Which physical arrow walks *back* to previous copies is configurable
        // (menu → Arrow Direction). Up always pairs with Left, Down with Right.
        let leftIsOlder = Settings.previousArrow == .left
        let mods = event.modifierFlags
        let code = Int(event.keyCode)

        // Modified vertical arrows scroll the preview instead of walking history —
        // tested *before* the plain-arrow cases below, which match on key code alone
        // and would otherwise fire on ⌥↑ / ⌘↓ as well.
        if code == kVK_UpArrow || code == kVK_DownArrow {
            let up = code == kVK_UpArrow
            if mods.contains(.option) {
                onKey?(up ? .scrollUp : .scrollDown)
                return
            }
            if mods.contains(.command) {
                onKey?(up ? .scrollToStart : .scrollToEnd)
                return
            }
        }

        switch code {
        case kVK_PageUp:
            onKey?(.scrollPageUp)
        case kVK_PageDown:
            onKey?(.scrollPageDown)
        case kVK_Home:
            onKey?(.scrollToStart)
        case kVK_End:
            onKey?(.scrollToEnd)
        case kVK_LeftArrow, kVK_UpArrow:
            onKey?(leftIsOlder ? .older : .newer)
        case kVK_RightArrow, kVK_DownArrow:
            onKey?(leftIsOlder ? .newer : .older)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // ⇧ reflows terminal output then pastes formatted; ⌥ pastes with
            // formatting; plain ⏎ stays the default.
            if mods.contains(.shift) {
                onKey?(.pasteReflow)
            } else if mods.contains(.option) {
                onKey?(.pasteRich)
            } else {
                onKey?(.paste)
            }
        case kVK_Escape:
            onKey?(.dismiss)
        case kVK_Delete, kVK_ForwardDelete:
            onKey?(.delete)
        case kVK_ANSI_Slash:
            // vi-style: "/" drops the carousel into search-the-history mode.
            onKey?(.search)
        default:
            super.keyDown(with: event)
        }
    }

    // Esc routes here for borderless panels.
    override func cancelOperation(_ sender: Any?) {
        onKey?(.dismiss)
    }
}
