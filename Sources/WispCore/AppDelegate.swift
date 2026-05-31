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
    private var maxClipItems: [NSMenuItem] = []
    private var directionItems: [NSMenuItem] = []
    private var keepFormattingItem: NSMenuItem?
    private var appearanceItems: [NSMenuItem] = []

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
            button.image = statusItemImage()
            button.toolTip = "\(AppInfo.name) — \(AppInfo.tagline)"
        }
        item.menu = buildMenu()
        statusItem = item
    }

    /// The menu bar glyph. Prefers the bundled Wisp template (the stacked-clips
    /// mark in Resources/MenuBarIcon.pdf), which renders as a monochrome
    /// template that macOS tints for light and dark menu bars. Falls back to an
    /// SF Symbol if the resource is missing (e.g. running from a bare build).
    private func statusItemImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = AppInfo.name
            return image
        }
        let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: AppInfo.name)
        fallback?.isTemplate = true
        return fallback
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

        // Max clip size submenu — your per-clip memory budget (covers text and HTML).
        let clipParent = NSMenuItem(title: "Max Clip Size", action: nil, keyEquivalent: "")
        let clipMenu = NSMenu()
        maxClipItems = Settings.allowedMaxClipByteSizes.map { bytes in
            let item = NSMenuItem(title: Settings.clipSizeLabel(bytes),
                                  action: #selector(changeMaxClipSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = bytes
            clipMenu.addItem(item)
            return item
        }
        clipParent.submenu = clipMenu
        menu.addItem(clipParent)

        // Arrow direction submenu — which arrow walks back to previous copies.
        let dirParent = NSMenuItem(title: "Arrow Direction", action: nil, keyEquivalent: "")
        let dirMenu = NSMenu()
        let dirOptions: [(Settings.ArrowDirection, String)] = [
            (.left,  "← Previous   → Next"),
            (.right, "→ Previous   ← Next")
        ]
        directionItems = dirOptions.map { direction, label in
            let item = NSMenuItem(title: label, action: #selector(changeDirection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = direction.rawValue
            dirMenu.addItem(item)
            return item
        }
        dirParent.submenu = dirMenu
        menu.addItem(dirParent)

        // Keep the source app's formatting in memory so ⌥⏎ pastes it faithfully.
        let keepFormatting = NSMenuItem(title: "Keep Source Formatting (⌥⏎)",
                                        action: #selector(toggleKeepFormatting), keyEquivalent: "")
        keepFormatting.target = self
        menu.addItem(keepFormatting)
        keepFormattingItem = keepFormatting

        // Bezel appearance — force the card's shade so the translucent material
        // stays legible over any desktop (default Dark).
        let appearanceParent = NSMenuItem(title: "Bezel Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        let appearanceOptions: [(Settings.BezelAppearance, String)] = [
            (.dark,  "Dark"),
            (.light, "Light"),
            (.auto,  "Auto (match System)")
        ]
        appearanceItems = appearanceOptions.map { appearance, label in
            let item = NSMenuItem(title: label, action: #selector(changeBezelAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appearance.rawValue
            appearanceMenu.addItem(item)
            return item
        }
        appearanceParent.submenu = appearanceMenu
        menu.addItem(appearanceParent)

        // Bezel transparency — a live Translucent↔Solid slider (custom menu view).
        // Dragging restyles the bezel on screen in real time: the controller pops it
        // up as a focus-preserving preview (so this menu stays open) and tears it
        // down when the menu closes (see menuDidClose).
        let transparency = NSMenuItem()
        transparency.view = TransparencySliderView(value: Settings.bezelSolidness) { [weak self] value in
            Settings.bezelSolidness = value
            self?.bezel.previewStyle()
        }
        menu.addItem(transparency)

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

        let checkUpdates = NSMenuItem(title: "Check for Updates…",
                                      action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        menu.addItem(checkUpdates)

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

    @objc private func changeMaxClipSize(_ sender: NSMenuItem) {
        // Applies to clips captured from here on; existing entries are left as-is
        // (Clear History drops any older large ones).
        Settings.maxClipBytes = sender.tag
    }

    @objc private func changeDirection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let direction = Settings.ArrowDirection(rawValue: raw) else { return }
        Settings.previousArrow = direction
    }

    @objc private func toggleKeepFormatting() {
        Settings.keepFormatting.toggle()
    }

    @objc private func changeBezelAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let appearance = Settings.BezelAppearance(rawValue: raw) else { return }
        Settings.bezelAppearance = appearance
        bezel.previewStyle() // reflect the new shade live, like the transparency slider
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled)
    }

    @objc private func openAccessibility() {
        AccessibilityAuthorizer.requestIfNeeded()
        AccessibilityAuthorizer.openSettings()
    }

    @objc private func checkForUpdates() {
        // Wisp itself never touches the network (see docs/SECURITY.md). This hands
        // the latest-release page to the user's browser, which shows the newest
        // version and the build-from-source install steps — the comparison is
        // theirs to make (the menu title above shows the running version).
        NSWorkspace.shared.open(AppInfo.latestReleaseURL)
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
        for item in maxClipItems {
            item.state = (item.tag == Settings.maxClipBytes) ? .on : .off
        }
        for item in directionItems {
            let raw = item.representedObject as? String
            item.state = (raw == Settings.previousArrow.rawValue) ? .on : .off
        }
        keepFormattingItem?.state = Settings.keepFormatting ? .on : .off
        for item in appearanceItems {
            let raw = item.representedObject as? String
            item.state = (raw == Settings.bezelAppearance.rawValue) ? .on : .off
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

    /// When the menu closes, dismiss any live style preview the transparency slider
    /// popped up. No-op if the bezel was opened for real.
    func menuDidClose(_ menu: NSMenu) {
        bezel.endPreview()
    }
}

// MARK: - Transparency slider (custom menu item view)

/// A menu-embedded slider for the bezel's Translucent↔Solid setting: a title row
/// over a slider flanked by end-stop captions. Reports its value continuously as
/// the user drags; the menu stays open while interacting (standard for view-based
/// items), so the change is saved immediately and applied the next time the bezel
/// is shown.
@MainActor
final class TransparencySliderView: NSView {
    private let slider = NSSlider()
    private let onChange: (Double) -> Void

    init(value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Bezel Transparency")
        title.font = .systemFont(ofSize: 13)
        title.textColor = .labelColor

        let left = caption("Translucent")
        let right = caption("Solid")

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = min(max(value, 0), 1)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)

        for view in [title, left, slider, right] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 240),
            heightAnchor.constraint(equalToConstant: 56),

            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: slider.centerYAnchor),

            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            right.centerYAnchor.constraint(equalTo: slider.centerYAnchor),

            slider.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            slider.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 10)
        field.textColor = .tertiaryLabelColor
        return field
    }

    @objc private func sliderChanged() {
        onChange(slider.doubleValue)
    }
}
