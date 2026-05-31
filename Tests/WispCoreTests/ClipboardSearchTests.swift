import Testing
@testable import WispCore

struct ClipboardSearchTests {
    private func items(_ texts: [String]) -> [ClipboardItem] {
        texts.map { ClipboardItem(text: $0) }
    }

    // MARK: - Empty query

    @Test func emptyQueryReturnsEverythingInHistoryOrder() {
        let results = ClipboardSearch.search("", in: items(["a", "b", "c"]))
        #expect(results.map(\.item.text) == ["a", "b", "c"])
        #expect(results.allSatisfy { $0.score == 0 && $0.matchedOffsets.isEmpty })
    }

    @Test func whitespaceQueryIsTreatedAsEmpty() {
        let results = ClipboardSearch.search("   \n", in: items(["x", "y"]))
        #expect(results.map(\.item.text) == ["x", "y"])
    }

    // MARK: - Substring matching

    @Test func nonMatchesAreExcluded() {
        let results = ClipboardSearch.search("zzz", in: items(["hello", "world"]))
        #expect(results.isEmpty)
    }

    @Test func substringMatchesAreFound() {
        let results = ClipboardSearch.search("wor", in: items(["hello", "a world", "words"]))
        #expect(Set(results.map(\.item.text)) == ["a world", "words"])
    }

    @Test func matchingIsCaseInsensitive() {
        let results = ClipboardSearch.search("HELLO", in: items(["hello world"]))
        #expect(results.count == 1)
    }

    @Test func matchesMidWordSubstrings() {
        // "engine" should still match where it genuinely occurs, even inside a word.
        let results = ClipboardSearch.search("engine", in: items(["the engineering team", "unrelated"]))
        #expect(results.map(\.item.text) == ["the engineering team"])
    }

    // MARK: - Precision (the bug this fixes)

    @Test func scatteredLettersDoNotMatch() {
        // "engine" (e-n-g-i-n-e) appears as a *subsequence* of this sentence but the
        // word never does — the old fuzzy matcher matched it; substring must not.
        let results = ClipboardSearch.search("engine", in: items(["enter the green line easily now"]))
        #expect(results.isEmpty)
    }

    // MARK: - Multi-term (AND)

    @Test func everyTermMustMatch() {
        let corpus = items(["google cli reference", "cli only here", "go home now"])
        let results = ClipboardSearch.search("go cli", in: corpus)
        // "google cli reference" has both "go" (in google) and "cli"; the others miss one.
        #expect(results.map(\.item.text) == ["google cli reference"])
    }

    @Test func termsMatchInAnyOrder() {
        let results = ClipboardSearch.search("cli google", in: items(["google cli reference"]))
        #expect(results.count == 1)
    }

    // MARK: - Ranking

    @Test func wordStartOutranksMidWord() {
        let results = ClipboardSearch.search("cat", in: items(["a scattered note", "cat nap"]))
        #expect(results.first?.item.text == "cat nap")
    }

    @Test func contiguousWholeQueryOutranksSplit() {
        let results = ClipboardSearch.search("new york", in: items(["new big york park", "visit new york city"]))
        #expect(results.first?.item.text == "visit new york city")
    }

    @Test func recencyBreaksScoreTies() {
        // Both score identically for "ab" (word-start at 0); the newer entry wins.
        let results = ClipboardSearch.search("ab", in: items(["abc", "abx"]))
        #expect(results.map(\.item.text) == ["abc", "abx"])
    }

    // MARK: - Matched offsets (for highlighting)

    @Test func matchedOffsetsCoverTheMatchedSubstring() {
        let text = "alpha\n  beta gamma\ndelta"
        let results = ClipboardSearch.search("beta", in: items([text]))
        #expect(results.first?.matchedOffsets == [8, 9, 10, 11])
    }

    @Test func matchedOffsetsSpanAllTerms() {
        let results = ClipboardSearch.search("a c", in: items(["a b c"]))
        // "a" at 0, "c" at 4.
        #expect(results.first?.matchedOffsets == [0, 4])
    }

    // MARK: - Preview line

    @Test func previewLineReturnsTheLineAroundAnOffsetTrimmed() {
        let text = "alpha\n  beta gamma\ndelta"
        let (line, start) = ClipboardSearch.previewLine(for: text, around: 8)
        #expect(line == "beta gamma")
        #expect(start == 8) // leading two spaces trimmed off the second line
    }

    @Test func previewLineDefaultsToTheFirstLine() {
        let (line, start) = ClipboardSearch.previewLine(for: "first\nsecond", around: 0)
        #expect(line == "first")
        #expect(start == 0)
    }

    @Test func previewLineHandlesEmptyText() {
        let (line, start) = ClipboardSearch.previewLine(for: "", around: 0)
        #expect(line == "")
        #expect(start == 0)
    }
}
