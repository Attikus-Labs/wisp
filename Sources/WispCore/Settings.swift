import Foundation

/// Tiny `UserDefaults`-backed settings. We intentionally persist *preferences*
/// only — never clipboard contents (see the memory-only design in SECURITY.md).
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let historySize = "historySize"
        static let arrowDirection = "arrowDirection"
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
}
