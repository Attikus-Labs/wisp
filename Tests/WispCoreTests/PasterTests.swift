import Testing
import AppKit
@testable import WispCore

@MainActor
struct PasterTests {
    @Test func passthroughReEmitsSourceHTMLVerbatimWithoutRTF() {
        let item = Paster.formattedItem(text: "plain text", sourceHTML: "<p>rich <b>source</b></p>")
        #expect(item.string(forType: .string) == "plain text")
        #expect(item.string(forType: .html) == "<p>rich <b>source</b></p>") // verbatim
        // We must NOT parse untrusted source HTML (network risk), so no RTF.
        #expect(item.data(forType: .rtf) == nil)
    }

    @Test func synthesisRendersMarkdownAndDerivesRTF() {
        let item = Paster.formattedItem(text: "# Title\n\n- a", sourceHTML: nil)
        #expect(item.string(forType: .string) == "# Title\n\n- a")
        let html = item.string(forType: .html) ?? ""
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<li>a</li>"))
        #expect(item.data(forType: .rtf) != nil) // derived from our own (safe) HTML
    }

    @Test func emptySourceHTMLFallsBackToSynthesis() {
        let item = Paster.formattedItem(text: "**b**", sourceHTML: "")
        #expect((item.string(forType: .html) ?? "").contains("<strong>b</strong>"))
        #expect(item.data(forType: .rtf) != nil)
    }
}
