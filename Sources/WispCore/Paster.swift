import AppKit

/// Places text on the pasteboard and pastes it into the previously-active app by
/// synthesizing ⌘V. That synthetic keystroke is the *only* reason Wisp asks for
/// Accessibility — and if it's not granted, the text is still on the clipboard
/// so a manual ⌘V works.
@MainActor
enum Paster {
    /// Plain paste (default ⏎): place the text as-is. Exactly the original
    /// behaviour — what you copied is what lands.
    static func paste(_ text: String, into app: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        deliver(to: app)
    }

    /// Rich paste (⌥⏎): treat the entry as Markdown and place rich flavors
    /// alongside the plain text on a single pasteboard item. Rich targets (Slack,
    /// Notes, Mail…) render real formatting; plain-text editors (Sublime, Obsidian)
    /// still receive the original Markdown through the plain-text flavor. Wisp keeps
    /// storing only text — the HTML/RTF are generated here, at paste time, and never
    /// retained.
    static func pasteRich(_ text: String, into app: NSRunningApplication?) {
        let fragment = MarkdownRenderer.html(from: text)
        let document = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(fragment)</body></html>"

        let item = NSPasteboardItem()
        // Plain-text flavor is the original Markdown: best for code/markdown editors.
        item.setString(text, forType: .string)
        item.setString(document, forType: .html)
        if let rtf = rtfData(fromHTML: document) {
            item.setData(rtf, forType: .rtf)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        deliver(to: app)
    }

    /// Return focus to the previous app and synthesize ⌘V (if allowed). Shared by
    /// both paste paths. If Accessibility isn't granted, the clip is on the board
    /// regardless — a manual ⌘V still works.
    private static func deliver(to app: NSRunningApplication?) {
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

    /// Best-effort RTF derived from our *own* (trusted, resource-free) HTML, so
    /// RTF-first targets get formatting too. Returns nil on failure — we then just
    /// ship plain text + HTML. The HTML importer is WebKit-backed and main-thread
    /// only; we're already on the main actor, and our HTML references no external
    /// resources, so there's no network fetch.
    private static func rtfData(fromHTML html: String) -> Data? {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html,
                            .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil)
        else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
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
