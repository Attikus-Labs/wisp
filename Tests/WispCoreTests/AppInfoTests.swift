import Testing
@testable import WispCore

struct AppInfoTests {
    // "Check for Updates…" opens this URL in the browser, so a malformed path
    // (e.g. a stray percent-encoded slash) would silently send users nowhere
    // useful. Pin the exact string.
    @Test func latestReleaseURLPointsAtGitHubReleases() {
        #expect(AppInfo.latestReleaseURL.absoluteString
            == "https://github.com/Attikus-Labs/wisp/releases/latest")
    }
}
