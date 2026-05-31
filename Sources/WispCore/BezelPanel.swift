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
}

/// Borderless floating panel that hosts the bezel. It overrides `canBecomeKey`
/// so it can receive arrow keys despite having no title bar.
@MainActor
final class BezelPanel: NSPanel {
    var onKey: ((BezelKey) -> Void)?

    init(contentView: NSView) {
        super.init(contentRect: contentView.bounds,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        self.contentView = contentView
        isFloatingPanel = true
        level = .modalPanel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
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
        switch Int(event.keyCode) {
        case kVK_LeftArrow, kVK_UpArrow:
            onKey?(leftIsOlder ? .older : .newer)
        case kVK_RightArrow, kVK_DownArrow:
            onKey?(leftIsOlder ? .newer : .older)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // ⇧ reflows terminal output then pastes formatted; ⌥ pastes with
            // formatting; plain ⏎ stays the default.
            let mods = event.modifierFlags
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
