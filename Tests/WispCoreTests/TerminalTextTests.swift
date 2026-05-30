import Testing
@testable import WispCore

struct TerminalTextTests {
    private func reflow(_ s: String) -> String { TerminalText.reflow(s) }

    // MARK: - Detection

    @Test func detectsTerminalGlyphs() {
        #expect(TerminalText.looksLikeTerminalOutput("• one\n• two"))
        #expect(TerminalText.looksLikeTerminalOutput("├── a\n└── b"))
        #expect(TerminalText.looksLikeTerminalOutput("\u{001B}[31mred\u{001B}[0m"))
    }

    @Test func quietForOrdinaryMarkdown() {
        let md = "# Heading\n\n- item one\n- item two\n\nA **bold** word and `code`."
        #expect(!TerminalText.looksLikeTerminalOutput(md))
    }

    // MARK: - Reflow

    @Test func stripsAnsiEscapes() {
        let out = reflow("\u{001B}[1;32mhello\u{001B}[0m world")
        #expect(out == "hello world")
    }

    @Test func convertsBulletGlyphsToMarkdown() {
        let out = reflow("• one\n• two")
        #expect(out.contains("- one"))
        #expect(out.contains("- two"))
        #expect(!out.contains("•"))
    }

    @Test func convertsBoxTreeToList() {
        let out = reflow("src\n├── a.swift\n└── b.swift")
        #expect(out.contains("- a.swift"))
        #expect(out.contains("- b.swift"))
        #expect(!out.contains("├"))
        #expect(!out.contains("└"))
    }

    @Test func dewrapsHardWrappedParagraph() {
        let wrapped = "This is a long paragraph that the\nterminal hard-wrapped across\nthree lines."
        let out = reflow(wrapped)
        #expect(out == "This is a long paragraph that the terminal hard-wrapped across three lines.")
    }

    @Test func preservesParagraphBreaks() {
        let out = reflow("first para line one\nline two\n\nsecond para")
        #expect(out == "first para line one line two\n\nsecond para")
    }

    @Test func keepsListItemsSeparate() {
        let out = reflow("- alpha\n- beta\n- gamma")
        #expect(out == "- alpha\n- beta\n- gamma")
    }

    @Test func wrappedListItemContinuationJoinsToItem() {
        let out = reflow("- a list item that wrapped\n  onto a second line\n- next item")
        #expect(out.contains("- a list item that wrapped onto a second line"))
        #expect(out.contains("- next item"))
    }

    @Test func leavesFencedCodeIntact() {
        let code = "```\nlet a = 1\nlet b = 2\n```"
        // Lines inside the fence must not be joined together.
        #expect(reflow(code).contains("let a = 1\nlet b = 2"))
    }

    @Test func boxTreePreservesIndent() {
        let out = reflow("root\n    ├── a\n    └── b")
        #expect(out.contains("    - a"))
        #expect(out.contains("    - b"))
    }

    @Test func contentlessBulletIsDropped() {
        let out = reflow("•\n• real item")
        #expect(out.contains("- real item"))
        #expect(!out.contains("•"))
    }

    @Test func collapsesExtraBlankLines() {
        let out = reflow("a\n\n\n\nb")
        #expect(out == "a\n\nb")
    }

    @Test func emptyStaysEmpty() {
        #expect(reflow("").isEmpty)
        #expect(reflow("\u{001B}[0m\n\n  ").isEmpty)
    }
}
