import Foundation

/// Tiny `UserDefaults`-backed settings. We intentionally persist *preferences*
/// only — never clipboard contents (see the memory-only design in SECURITY.md).
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let historySize = "historySize"
        static let arrowDirection = "arrowDirection"
        static let keepFormatting = "keepFormatting"
        static let maxClipBytes = "maxClipBytes"
    }

    static let allowedHistorySizes = [10, 20, 40, 80]
    static let defaultHistorySize = 40

    static var historySize: Int {
        get {
            let value = defaults.integer(forKey: Key.historySize)
            return allowedHistorySizes.contains(value) ? value : defaultHistorySize
        }
        set { defaults.set(newValue, forKey: Key.historySize) }
    }

    /// Per-clip size budget in **bytes**, applied to every field Wisp would retain —
    /// the plain text *and* the optional captured HTML alike. You set it, so you
    /// decide how much memory the history may use: a small cap keeps Wisp featherweight
    /// and refuses to remember giant clips (they stay on the system pasteboard, so a
    /// plain ⌘V still works); a large cap — or `unlimitedClipBytes` — lets you keep big
    /// pastes when that's worth the RAM. A clip whose *text* exceeds the cap isn't
    /// recorded at all; *HTML* over the cap is dropped while the text is kept (⌥⏎ then
    /// falls back to Markdown synthesis). Memory-only, like everything else here.
    static let unlimitedClipBytes = 0
    static let allowedMaxClipByteSizes = [1_000_000, 2_000_000, 5_000_000, 10_000_000, 50_000_000, unlimitedClipBytes]
    static let defaultMaxClipBytes = 2_000_000

    static var maxClipBytes: Int {
        // The getter is the single validation point: any non-negative `Int` is honored
        // (power users can `defaults write` an arbitrary budget), while a missing,
        // non-`Int`, or negative value falls back to the default. The setter stores
        // raw so a stray negative resolves to the default here, not to 0 (= unlimited).
        get {
            guard let value = defaults.object(forKey: Key.maxClipBytes) as? Int, value >= 0
            else { return defaultMaxClipBytes }
            return value
        }
        set { defaults.set(newValue, forKey: Key.maxClipBytes) }
    }

    /// Menu label for a clip-size budget: "Unlimited" or whole-megabyte presets.
    static func clipSizeLabel(_ bytes: Int) -> String {
        bytes == unlimitedClipBytes ? "Unlimited" : "\(bytes / 1_000_000) MB"
    }

    /// Which horizontal arrow steps to the *previous* (older) clip; the opposite
    /// arrow steps toward the newest. Up pairs with Left, Down with Right.
    enum ArrowDirection: String, CaseIterable {
        case left   // ← / ↑ = previous (older), → / ↓ = newer
        case right  // → / ↓ = previous (older), ← / ↑ = newer
    }

    static let defaultArrowDirection: ArrowDirection = .left

    /// The arrow that walks back to previous copies. Defaults to ←, so → / ↓
    /// step toward the most-recent copy ("next").
    static var previousArrow: ArrowDirection {
        get {
            defaults.string(forKey: Key.arrowDirection)
                .flatMap(ArrowDirection.init(rawValue:)) ?? defaultArrowDirection
        }
        set { defaults.set(newValue.rawValue, forKey: Key.arrowDirection) }
    }

    /// Whether to also keep the source app's rich HTML in memory, so a formatted
    /// paste (⌥⏎) can reproduce the original formatting (e.g. select-and-copy from
    /// Claude). Default on. Turn off for a strictly plain-text history. Only the
    /// preference is persisted — never any clipboard content.
    static var keepFormatting: Bool {
        get { defaults.object(forKey: Key.keepFormatting) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.keepFormatting) }
    }
}
