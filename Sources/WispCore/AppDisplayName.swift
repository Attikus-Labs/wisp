import AppKit

/// Resolves a bundle id to a human app name (e.g. "com.apple.Safari" → "Safari"),
/// memoised across the process. The lookup is a synchronous Launch Services /
/// filesystem call, and both the bezel and the search list redraw it on every
/// keystroke, so the cache keeps navigation cheap. An empty cached value means
/// "no resolvable name" (so we don't retry a miss).
@MainActor
enum AppDisplayName {
    private static var cache: [String: String] = [:]

    static func resolve(_ bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached.isEmpty ? nil : cached }
        let resolved = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
        cache[bundleID] = resolved ?? ""
        return resolved
    }
}
