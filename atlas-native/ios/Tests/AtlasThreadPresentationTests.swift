import Foundation
import Testing

@MainActor
struct AtlasThreadPresentationTests {
    @Test func voiceTranscriptPreservesTypedDraftAndRequiresNonemptyText() {
        #expect(AtlasVoiceInput.appending(" local words ", to: "Typed draft") == "Typed draft local words")
        #expect(AtlasVoiceInput.appending(" words ", to: "Typed\n") == "Typed\nwords")
        #expect(AtlasVoiceInput.appending(" \n ", to: "Unchanged") == "Unchanged")
        #expect(AtlasVoiceInput.appending(" words ", to: "") == "words")
    }

    @Test func markdownRendersStructureAndKeepsCodeLiteral() {
        let source = "# Heading\n\n**Bold** and [a link](https://example.org)\n\n- first\n1. second\n> quote\n\n"
            + "```swift\nlet x = \"**literal**\"\n```\n\n| Name | Value |\n| --- | ---: |\n| Count | 12 |"
        #expect(AtlasMarkdownBlock.parse(source) == [
            .heading(1, "Heading"), .paragraph("**Bold** and [a link](https://example.org)"),
            .list("•", "first"), .list("1.", "second"), .quote("quote"),
            .code("swift", "let x = \"**literal**\""), .table([["Name", "Value"], ["Count", "12"]])
        ])
        #expect(String(AtlasMarkdown.inline("**Bold** and `code`").characters) == "Bold and code")
    }

    @Test func markdownNeverExecutesLinksOrLoadsImages() {
        let unsafe = AtlasMarkdown.inline("[Open](dev.tuist.atlas://navigate/accounts)")
        #expect(unsafe.runs.allSatisfy { $0.link == nil })
        let safe = AtlasMarkdown.inline("[Open](https://example.org)")
        #expect(safe.runs.contains { $0.link?.scheme == "https" })
        #expect(AtlasMarkdownBlock.parse("```\nunclosed **code**") == [.code("", "unclosed **code**")])
        #expect(AtlasMarkdownBlock.parse(String(repeating: "x", count: 20_000)) == [.paragraph(String(repeating: "x", count: 16_000))])
    }
}
