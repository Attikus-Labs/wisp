import AppKit
import ApplicationServices

/// Wisp needs the Accessibility permission for exactly one thing: synthesizing
/// ⌘V to paste into the app you were just using. Nothing else — no global key
/// logging, no event taps.
enum AccessibilityAuthorizer {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user (once) to grant Accessibility, surfacing the system
    /// dialog that deep-links to System Settings.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility pane directly.
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
