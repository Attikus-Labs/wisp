import AppKit

/// Public entry point. The `Wisp` executable target is just a one-liner that
/// calls this, keeping all real code in the testable `WispCore` library.
public enum WispApp {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        // Menu-bar agent: no Dock icon, no main window.
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate // NSApplication holds this weakly…

        // …so keep the delegate alive for the whole run loop.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
