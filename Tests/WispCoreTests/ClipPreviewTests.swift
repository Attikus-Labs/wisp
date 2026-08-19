import Testing
import Foundation
@testable import WispCore

/// The pure text helpers behind the bezel's and the search HUD's previews: what
/// gets trimmed away before a clip is shown, how a clip's size is summarised, and
/// how `ClipboardSearch`'s character offsets are mapped onto the trimmed preview so
/// the right characters are highlighted.
struct ClipPreviewTests {
    // MARK: - trimmedPreview

    @Test func dropsLeadingBlankLinesAndReportsHowMany() {
        let (text, dropped) = ClipPreview.trimmedPreview("\n\n\r  indented")
        #expect(text == "  indented")
        #expect(dropped == 3)
    }

    @Test func countsACRLFPrefixAsTheSingleCharacterItIs() {
        // "\r\n" is one Character — both here and in the offsets ClipboardSearch
        // reports — so dropping it must shift matches by one, not two.
        let (text, dropped) = ClipPreview.trimmedPreview("\r\n\r\nfox")
        #expect(text == "fox")
        #expect(dropped == 2)
    }

    @Test func keepsLeadingSpacesAndDropsTrailingWhitespace() {
        // Leading spaces are the clip's own indentation — they're shown against the
        // container edge — while trailing whitespace would only waste preview height.
        let (text, dropped) = ClipPreview.trimmedPreview("    let x = 1\n\n   \n")
        #expect(text == "    let x = 1")
        #expect(dropped == 0)
    }

    @Test func emptyAndWhitespaceOnlyClipsTrimToNothing() {
        #expect(ClipPreview.trimmedPreview("").text == "")
        #expect(ClipPreview.trimmedPreview("\n \n").text == "")
    }

    // MARK: - lineCount / sizeSummary

    @Test func countsLinesAfterTrimming() {
        #expect(ClipPreview.lineCount(of: "").lines == 0)
        #expect(ClipPreview.lineCount(of: "one line").lines == 1)
        #expect(ClipPreview.lineCount(of: "a\nb\nc").lines == 3)
        // Leading blank lines and trailing whitespace are dropped by the preview, so
        // they mustn't inflate the count the HUDs report either.
        #expect(ClipPreview.lineCount(of: "a\nb\n\n\n").lines == 2)
        #expect(ClipPreview.lineCount(of: "\n\n\na\nb").lines == 2)
        #expect(ClipPreview.lineCount(of: "\n  \n").lines == 0)
    }

    @Test func countsLinesByteWiseWithoutMiscountingMultiByteText() {
        // The count walks UTF-8, so multi-byte scalars must not register as breaks.
        #expect(ClipPreview.lineCount(of: "héllo 🙂 wörld").lines == 1)
        #expect(ClipPreview.lineCount(of: "héllo\n🙂\nwörld").lines == 3)
        // CRLF is one break, and a lone CR (a terminal redrawing a line in place) is
        // not a new line at all.
        #expect(ClipPreview.lineCount(of: "a\r\nb").lines == 2)
        #expect(ClipPreview.lineCount(of: "50%\r75%\r100%").lines == 1)
    }

    @Test func hugeClipsReportAFloorRatherThanScanningEverything() {
        // Beyond the scan cap the count is a lower bound — the search list computes
        // one of these per result on every keystroke.
        let huge = String(repeating: "x\n", count: ClipPreview.maxCountedBytes)
        let count = ClipPreview.lineCount(of: huge)
        #expect(count.partial)
        #expect(count.lines > 1)
        #expect(count.lines < huge.utf8.count / 2) // it stopped early, as intended
        #expect(ClipPreview.lineLabel(of: huge)?.hasSuffix("+ lines") == true)
    }

    @Test func lineLabelIsOmittedForOneLiners() {
        #expect(ClipPreview.lineLabel(of: "just one line") == nil)
        #expect(ClipPreview.lineLabel(of: "") == nil)
        #expect(ClipPreview.lineLabel(of: "a\nb") == "2 lines")
    }

    @Test func sizeSummaryDropsLineCountForOneLiners() {
        #expect(ClipPreview.sizeSummary("x") == "1 char")
        #expect(ClipPreview.sizeSummary("hello") == "5 chars")
    }

    @Test func sizeSummaryReportsLinesAndTheWholeClipsLength() {
        let text = "a\nb\nc"
        let summary = ClipPreview.sizeSummary(text)
        #expect(summary.hasPrefix("3 lines"))
        #expect(summary.contains("5 chars")) // the full clip, not the trimmed preview
    }

    @Test func sizeSummarySwitchesToAByteSizeForHugeClips() {
        // "12,345,678 chars" says less than "12.3 MB" — and counting grapheme
        // clusters over a clip that size is work with nothing to show for it.
        let huge = String(repeating: "x", count: ClipPreview.maxMeasuredBytes + 1)
        let summary = ClipPreview.sizeSummary(huge)
        #expect(!summary.contains("chars"))
        // The unit itself is localised ("MB" / "Mo"), so assert on the shape only.
        #expect(summary.rangeOfCharacter(from: .decimalDigits) != nil)
    }

    // MARK: - highlightRanges

    @Test func shiftsOffsetsPastTheTrimmedPrefix() {
        // "\n\nfox" — a match on "fox" at clip offsets 2...4 lands at 0...2 once the
        // two leading newlines are dropped for display.
        let (preview, dropped) = ClipPreview.trimmedPreview("\n\nfox trot")
        let ranges = ClipPreview.highlightRanges(in: String(preview), matchedOffsets: [2, 3, 4], dropped: dropped)
        #expect(ranges == [NSRange(location: 0, length: 3)])
    }

    @Test func mergesAdjacentOffsetsAndKeepsGapsApart() {
        // Two separate matched runs stay two ranges; adjacent characters collapse.
        let ranges = ClipPreview.highlightRanges(in: "abcdefghij", matchedOffsets: [1, 2, 3, 7, 8], dropped: 0)
        #expect(ranges == [NSRange(location: 1, length: 3), NSRange(location: 7, length: 2)])
    }

    @Test func dropsOffsetsOutsideThePreview() {
        // Offsets before the kept text (inside the trimmed prefix) or past its end —
        // e.g. a match beyond the preview cap — are ignored rather than mis-highlighted.
        let ranges = ClipPreview.highlightRanges(in: "abc", matchedOffsets: [0, 99], dropped: 2)
        #expect(ranges.isEmpty)
    }

    @Test func noMatchesMeansNoHighlights() {
        #expect(ClipPreview.highlightRanges(in: "abc", matchedOffsets: [], dropped: 0).isEmpty)
        #expect(ClipPreview.highlightRanges(in: "", matchedOffsets: [0], dropped: 0).isEmpty)
    }

    @Test func highlightRangesAreUTF16RangesOverTheDisplayedText() {
        // Emoji are two UTF-16 units but one Character: the ranges have to index the
        // string the way AppKit will, or the highlight lands on the wrong glyph.
        let preview = "🙂fox"
        let ranges = ClipPreview.highlightRanges(in: preview, matchedOffsets: [1, 2, 3], dropped: 0)
        #expect(ranges.count == 1)
        let substring = (preview as NSString).substring(with: ranges[0])
        #expect(substring == "fox")
    }
}
