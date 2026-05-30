import AppKit

/// Places text on the pasteboard and pastes it into the previously-active app by
/// synthesizing ⌘V. That synthetic keystroke is the *only* reason Wisp asks for
/// Accessibility — and if it's not granted, the text is still on the clipboard
/// so a manual ⌘V works.
@MainActor
enum Paster {
    static func paste(_ text: String, into app: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Return focus to wherever the user was, then paste there.
        app?.activate(options: [.activateIgnoringOtherApps])

        guard AccessibilityAuthorizer.isTrusted else {
            // No permission yet: nudge once. The clip is on the board regardless.
            AccessibilityAuthorizer.requestIfNeeded()
            return
        }

        // Let the activation land before we send the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendCommandV()
        }
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09 // 'v'
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
