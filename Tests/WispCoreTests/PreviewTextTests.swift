import Testing
@testable import WispCore

struct PreviewTextTests {
    @Test func passesShortTextThrough() {
        #expect(PreviewText.trimmed("hello world") == "hello world")
    }

    @Test func keepsLeadingSpaces() {
        // Leading spaces are revealed against the container edge — by design.
        #expect(PreviewText.trimmed("  indented") == "  indented")
    }

    @Test func dropsLeadingBlankLinesAndTrailingWhitespace() {
        #expect(PreviewText.trimmed("\n\n\nhello\n\n  ") == "hello")
    }

    @Test func dropsWindowsStyleLeadingBlankLines() {
        // A CRLF pair is one Character; it must still count as a blank line.
        #expect(PreviewText.trimmed("\r\n\r\nhello") == "hello")
    }

    /// The ordering bug this pins: blank lines are dropped BEFORE the cap, so a
    /// clip that *starts* with more blank lines than the whole cap still shows
    /// its content instead of nothing.
    @Test func contentSurvivesThousandsOfLeadingBlankLines() {
        let clip = String(repeating: "\n", count: PreviewText.displayCap + 1000) + "IMPORTANT"
        #expect(PreviewText.trimmed(clip) == "IMPORTANT")
    }

    @Test func capsOversizedText() {
        let clip = String(repeating: "x", count: PreviewText.displayCap + 500)
        #expect(PreviewText.trimmed(clip).count == PreviewText.displayCap)
    }

    /// When the cap cuts content short, trailing whitespace is deliberately
    /// kept: the label keeps overflowing, so the last-visible-line ellipsis
    /// keeps signalling "there's more" even if what follows the cut is blank.
    @Test func capCutKeepsTrailingWhitespaceAsOverflowSignal() {
        let clip = "abc" + String(repeating: "\n", count: PreviewText.displayCap)
            + "more content past the cap"
        let preview = PreviewText.trimmed(clip)
        #expect(preview.count == PreviewText.displayCap)
        #expect(preview.hasPrefix("abc"))
        #expect(preview.hasSuffix("\n"))
    }

    @Test func allBlankClipTrimsToEmpty() {
        #expect(PreviewText.trimmed("\n\n\n") == "")
        #expect(PreviewText.trimmed("") == "")
    }
}
