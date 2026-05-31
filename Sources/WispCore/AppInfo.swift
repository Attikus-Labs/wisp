import Foundation

/// Branding and a few constants kept in one place so renaming/forking is a
/// one-file change.
enum AppInfo {
    static let name = "Wisp"
    static let tagline = "A light, fast, secure clipboard for macOS"

    /// Single source of truth for the project page. Update if you fork/rename.
    static let repoURL = URL(string: "https://github.com/Attikus-Labs/wisp")!

    /// Where "Check for Updates…" sends people. GitHub redirects
    /// `/releases/latest` to the newest published release, whose notes carry the
    /// build-from-source install steps. Derived from `repoURL` so a fork/rename
    /// stays a one-file change. Wisp itself never fetches this — the browser
    /// does (see the Network section in docs/SECURITY.md).
    static var latestReleaseURL: URL {
        repoURL.appendingPathComponent("releases").appendingPathComponent("latest")
    }

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}
