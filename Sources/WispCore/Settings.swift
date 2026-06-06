import Foundation

/// Tiny `UserDefaults`-backed settings. We intentionally persist *preferences*
/// only — never clipboard contents (see the memory-only design in SECURITY.md).
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let historySize = "historySize"
        static let arrowDirection = "arrowDirection"
        static let maxClipBytes = "maxClipBytes"
        static let bezelAppearance = "bezelAppearance"
        static let bezelSolidness = "bezelSolidness"
        static let pasteClearSeconds = "pasteClearSeconds"
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

    /// Seconds after a paste before Wisp wipes the system pasteboard — shrinking the
    /// window in which a pasted secret sits on the *shared* clipboard for any other app
    /// to read. `0` = never clear (the default: auto-clearing surprises people who
    /// expect to ⌘V again). The clear only fires if nothing else has touched the
    /// clipboard since Wisp's paste, so it never clobbers a fresh copy (see `Paster`).
    /// This mitigates, but cannot eliminate, the shared-pasteboard risk — docs/SECURITY.md.
    static let allowedPasteClearSeconds = [0, 10, 30]
    static let defaultPasteClearSeconds = 0

    static var pasteClearSeconds: Int {
        get {
            guard let value = defaults.object(forKey: Key.pasteClearSeconds) as? Int,
                  allowedPasteClearSeconds.contains(value) else { return defaultPasteClearSeconds }
            return value
        }
        set { defaults.set(newValue, forKey: Key.pasteClearSeconds) }
    }

    /// Menu label for a paste-clear delay: "Never" or "10s".
    static func pasteClearLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Never" : "\(seconds)s"
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

    /// How the bezel/search card renders its translucent material regardless of the
    /// desktop behind it. Defaults to `.dark` — the material samples what's behind
    /// the window, so over a light desktop an auto card washes out; forcing dark
    /// keeps it legible everywhere (like the system volume HUD). Raw strings only;
    /// the AppKit mapping lives in `BezelEffectView`.
    enum BezelAppearance: String, CaseIterable {
        case dark, light, auto
    }

    static let defaultBezelAppearance: BezelAppearance = .dark

    static var bezelAppearance: BezelAppearance {
        get {
            defaults.string(forKey: Key.bezelAppearance)
                .flatMap(BezelAppearance.init(rawValue:)) ?? defaultBezelAppearance
        }
        set { defaults.set(newValue.rawValue, forKey: Key.bezelAppearance) }
    }

    /// How solid the bezel card is: `0` = fully translucent (pure material, the
    /// classic look), `1` = a near-opaque surface with guaranteed contrast on any
    /// background. Anything between blends the two. Defaults to translucent.
    static let defaultBezelSolidness = 0.0

    static var bezelSolidness: Double {
        get {
            guard defaults.object(forKey: Key.bezelSolidness) != nil else { return defaultBezelSolidness }
            return min(max(defaults.double(forKey: Key.bezelSolidness), 0), 1)
        }
        set { defaults.set(min(max(newValue, 0), 1), forKey: Key.bezelSolidness) }
    }
}
