import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let history: ClipboardHistory
    private let monitor: ClipboardMonitor
    private let bezel: BezelController
    private var hotkey: GlobalHotkey?
    private var statusItem: NSStatusItem?

    // Menu items whose state changes at runtime.
    private var launchItem: NSMenuItem?
    private var accessibilityItem: NSMenuItem?
    private var sizeItems: [NSMenuItem] = []

    override init() {
        let history = ClipboardHistory(capacity: Settings.historySize)
        self.history = history
        self.monitor = ClipboardMonitor(history: history)
        self.bezel = BezelController(history: history)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        monitor.start()
        registerHotkey()
        // Ask for Accessibility up front so the very first paste just works.
        if !AccessibilityAuthorizer.isTrusted {
            AccessibilityAuthorizer.requestIfNeeded()
        }
    }

    private func registerHotkey() {
        // ⌘⇧V
        hotkey = GlobalHotkey(keyCode: UInt32(kVK_ANSI_V),
                              modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.bezel.toggle()
        }
    }

    // MARK: - Status bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "\(AppInfo.name) — \(AppInfo.tagline)"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "\(AppInfo.name) \(AppInfo.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Clipboard", action: #selector(showBezel), keyEquivalent: "v")
        show.keyEquivalentModifierMask = [.command, .shift]
        show.target = self
        menu.addItem(show)

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        // History size submenu.
        let sizeParent = NSMenuItem(title: "History Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        sizeItems = Settings.allowedHistorySizes.map { size in
            let item = NSMenuItem(title: "\(size) items", action: #selector(changeSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = size
            sizeMenu.addItem(item)
            return item
        }
        sizeParent.submenu = sizeMenu
        menu.addItem(sizeParent)

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        menu.addItem(launch)
        launchItem = launch

        let accessibility = NSMenuItem(title: "Enable Paste (Accessibility)…",
                                       action: #selector(openAccessibility), keyEquivalent: "")
        accessibility.target = self
        menu.addItem(accessibility)
        accessibilityItem = accessibility

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Actions

    @objc private func showBezel() {
        bezel.show()
    }

    @objc private func clearHistory() {
        history.clear()
    }

    @objc private func changeSize(_ sender: NSMenuItem) {
        Settings.historySize = sender.tag
        history.setCapacity(sender.tag)
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled)
    }

    @objc private func openAccessibility() {
        AccessibilityAuthorizer.requestIfNeeded()
        AccessibilityAuthorizer.openSettings()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) \(AppInfo.version)"
        alert.informativeText = """
        \(AppInfo.tagline)

        Memory-only clipboard history: nothing is written to disk and nothing \
        ever leaves your Mac. Passwords and transient copies are ignored.

        Open source · MIT License
        """
        alert.addButton(withTitle: "Open Project Page")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(AppInfo.repoURL)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login (SMAppService, macOS 13+)

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Wisp: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in sizeItems {
            item.state = (item.tag == history.capacity) ? .on : .off
        }
        launchItem?.state = isLaunchAtLoginEnabled ? .on : .off

        if AccessibilityAuthorizer.isTrusted {
            accessibilityItem?.title = "Paste Enabled ✓"
            accessibilityItem?.isEnabled = false
        } else {
            accessibilityItem?.title = "Enable Paste (Accessibility)…"
            accessibilityItem?.isEnabled = true
        }
    }
}
