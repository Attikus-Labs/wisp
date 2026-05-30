import Foundation

/// Tiny `UserDefaults`-backed settings. We intentionally persist *preferences*
/// only — never clipboard contents (see the memory-only design in SECURITY.md).
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let historySize = "historySize"
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
}
