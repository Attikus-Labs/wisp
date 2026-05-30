import Testing
@testable import WispCore

struct MarkdownRendererTests {
    private func render(_ md: String) -> String { MarkdownRenderer.html(from: md) }

    // MARK: - Inline

    @Test func boldAndItalicAndCode() {
        let html = render("Some **bold**, _italic_ and `code` text.")
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<em>italic</em>"))
        #expect(html.contains("<code>code</code>"))
        #expect(html.hasPrefix("<p>"))
    }

    @Test func boldWithAsterisksAndUnderscores() {
        #expect(render("a **x** b").contains("<strong>x</strong>"))
        #expect(render("a __x__ b").contains("<strong>x</strong>"))
        #expect(render("a *x* b").contains("<em>x</em>"))
    }

    @Test func underscoresInsideWordsAreLiteral() {
        // some_variable_name must not become italic.
        let html = render("call some_variable_name now")
        #expect(!html.contains("<em>"))
        #expect(html.contains("some_variable_name"))
    }

    @Test func spaceFlankedAsteriskIsNotEmphasis() {
        // "2 * 3 * 4" is arithmetic, not emphasis.
        let html = render("2 * 3 * 4")
        #expect(!html.contains("<em>"))
    }

    @Test func links() {
        let html = render("See [the docs](https://example.com/x).")
        #expect(html.contains("<a href=\"https://example.com/x\">the docs</a>"))
    }

    @Test func inlineCodeIsNotFormattedAndIsEscaped() {
        let html = render("Use `a < b && **c**` here")
        #expect(html.contains("<code>a &lt; b &amp;&amp; **c**</code>"))
        // The ** inside the code span must NOT have become <strong>.
        #expect(!html.contains("<strong>"))
    }

    @Test func htmlSpecialCharactersAreEscaped() {
        let html = render("1 < 2 & 3 > 0")
        #expect(html.contains("1 &lt; 2 &amp; 3 &gt; 0"))
        #expect(!html.contains("< 2"))
    }

    // MARK: - Blocks

    @Test func headings() {
        #expect(render("# Title").contains("<h1>Title</h1>"))
        #expect(render("### Sub").contains("<h3>Sub</h3>"))
        // A hash without a space is not a heading.
        #expect(render("#notaheading").contains("<p>"))
        #expect(!render("#notaheading").contains("<h1>"))
    }

    @Test func unorderedList() {
        let html = render("- one\n- two\n- three")
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>one</li>"))
        #expect(html.contains("<li>three</li>"))
        #expect(html.contains("</ul>"))
    }

    @Test func orderedList() {
        let html = render("1. first\n2. second")
        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>first</li>"))
        #expect(html.contains("<li>second</li>"))
        #expect(html.contains("</ol>"))
    }

    @Test func listItemsCarryInlineFormatting() {
        let html = render("- a **bold** item")
        #expect(html.contains("<li>a <strong>bold</strong> item</li>"))
    }

    @Test func fencedCodeBlockIsVerbatimAndEscaped() {
        let md = "```swift\nlet x = a < b && c\nprint(\"**hi**\")\n```"
        let html = render(md)
        #expect(html.contains("<pre><code class=\"language-swift\">"))
        #expect(html.contains("let x = a &lt; b &amp;&amp; c"))
        // No inline formatting applied inside code blocks.
        #expect(!html.contains("<strong>"))
        #expect(html.contains("</code></pre>"))
    }

    @Test func tildeFencedBlockIsVerbatim() {
        let html = render("~~~\ntilde body\n~~~")
        #expect(html.contains("<pre><code>tilde body</code></pre>"))
    }

    @Test func longFenceNotClosedByShorterInnerFence() {
        // A 4-backtick fence must survive an inner ``` / ~~~ line (CommonMark: a
        // closer uses the same char and is at least as long). This is what keeps a
        // verbatim terminal block whole when the captured output shows fences.
        let md = "````\ninner ``` still code\n~~~ also code\nend\n````"
        let html = render(md)
        #expect(html.components(separatedBy: "<pre><code").count - 1 == 1) // one block
        #expect(html.contains("end"))
        #expect(!html.contains("<p>")) // nothing leaked back into markdown
    }

    @Test func blockquote() {
        let html = render("> quoted line")
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("quoted line"))
        #expect(html.contains("</blockquote>"))
    }

    @Test func horizontalRule() {
        #expect(render("---").contains("<hr>"))
        #expect(render("***").contains("<hr>"))
    }

    @Test func paragraphsSeparatedByBlankLine() {
        let html = render("first para\n\nsecond para")
        #expect(html.contains("<p>first para</p>"))
        #expect(html.contains("<p>second para</p>"))
    }

    @Test func plainTextBecomesParagraph() {
        #expect(render("just text").contains("<p>just text</p>"))
    }

    @Test func singleNewlinesBecomeLineBreaks() {
        // Pasted assistant text uses newlines as real breaks — they must survive
        // as <br>, not collapse into one run-on paragraph.
        let html = render("line one\nline two\nline three")
        #expect(html.contains("line one<br>"))
        #expect(html.contains("line two<br>"))
        #expect(html.contains("line three"))
        #expect(!html.contains("line one line two")) // not collapsed
    }

    @Test func emptyInputProducesNoBlocks() {
        #expect(render("").isEmpty)
        #expect(render("\n\n   \n").isEmpty)
    }

    @Test func linkUrlQuoteIsAttributeEscaped() {
        // A quote in the URL must not break out of the href attribute.
        let html = render("See [x](https://e.com/a\"b) now")
        #expect(html.contains("href=\"https://e.com/a&quot;b\""))
        #expect(!html.contains("a\"b\">"))
    }

    @Test func unsafeLinkSchemesDropTheAnchor() {
        // javascript:/file:/data: must never become a live <a href>.
        for url in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,x"] {
            let html = render("[click](\(url))")
            #expect(!html.contains("<a "))
            #expect(html.contains("click")) // text is kept
        }
    }

    @Test func safeLinkSchemesStillRender() {
        #expect(render("[a](https://x.com)").contains("<a href=\"https://x.com\">a</a>"))
        #expect(render("[m](mailto:x@y.com)").contains("<a href=\"mailto:x@y.com\">m</a>"))
        #expect(render("[r](/local/path)").contains("<a href=\"/local/path\">r</a>")) // relative
    }

    @Test func preexistingSentinelDoesNotCorrupt() {
        // U+E000/U+E001 in the input must not collide with code-span placeholders.
        let html = render("\u{E000}0\u{E001} and `code`")
        #expect(html.contains("<code>code</code>"))
        #expect(html.components(separatedBy: "<code>").count - 1 == 1) // exactly one code span
    }

    @Test func mixedDocument() {
        let md = """
        # Heading

        Intro with **bold** and a [link](https://x.com).

        - item one
        - item two

        ```
        code = 1
        ```
        """
        let html = render(md)
        #expect(html.contains("<h1>Heading</h1>"))
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("<a href=\"https://x.com\">link</a>"))
        #expect(html.contains("<ul>"))
        #expect(html.contains("<pre><code>code = 1</code></pre>"))
    }
}
