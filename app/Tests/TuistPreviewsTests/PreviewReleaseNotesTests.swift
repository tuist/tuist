import Testing
import TuistServer

@testable import TuistPreviews

@Suite struct PreviewReleaseNotesTests {
    @Test(arguments: [nil, "", " \t\n\r\n"] as [String?])
    func empty_notes_have_no_summary(notes: String?) {
        #expect(ServerPreview.test(releaseNotes: notes).releaseNotesSummary == nil)
    }

    @Test(arguments: ["\n", "\r\n", "\r", "\u{2028}"])
    func summary_is_only_the_first_plain_text_line(newline: String) {
        let firstLine = "Build 204 <script>test</script> **QA**"
        let preview = ServerPreview.test(releaseNotes: " \n " + firstLine + "  " + newline + "Detailed instructions")
        #expect(preview.releaseNotesSummary == firstLine)
        #expect(preview.releaseNotes?.contains("Detailed instructions") == true)
    }
}
