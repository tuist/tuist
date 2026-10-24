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

    @Test func releasedHoldCannotStartAQueuedMicrophoneRequest() async {
        let voice = AtlasVoiceInput()
        let start = Task { await voice.start() }
        start.cancel()
        voice.review()
        await start.value
        #expect(voice.phase == .idle)
        #expect(voice.transcript.isEmpty)
        #expect(voice.errorMessage == nil)
    }

    @Test(arguments: [false, true]) func releasedPermissionPromptCannotActivateMicrophoneLater(waitingForMicrophone: Bool) async {
        var resumePermission: (() -> Void)?
        var microphoneRequested = false
        let voice = AtlasVoiceInput(speechPermission: {
            if waitingForMicrophone { return .authorized }
            return await withCheckedContinuation { continuation in
                resumePermission = { continuation.resume(returning: .authorized) }
            }
        }, microphonePermission: {
            microphoneRequested = true
            return await withCheckedContinuation { continuation in
                resumePermission = { continuation.resume(returning: true) }
            }
        })
        let pending = Task { await voice.start() }
        while resumePermission == nil { await Task.yield() }
        #expect(voice.phase == .requesting)
        voice.review()
        resumePermission?()
        await pending.value
        #expect(voice.phase == .idle)
        #expect(voice.transcript.isEmpty)
        #expect(voice.errorMessage?.contains("After allowing permissions") == true)
        #expect(microphoneRequested == waitingForMicrophone)
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
