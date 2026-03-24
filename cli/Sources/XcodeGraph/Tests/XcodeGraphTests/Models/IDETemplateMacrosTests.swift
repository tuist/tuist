import Testing
import XcodeGraph

struct IDETemplateMacrosTests {
    @Test func removing_leading_comment_slashes() {
        // Given
        let fileHeader = "// Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(templateMacros.fileHeader == " Some template")
    }

    @Test func space_preservation_if_leading_comment_slashes_are_present() {
        // Given
        let fileHeader = "//Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(templateMacros.fileHeader == "Some template")
    }

    @Test func removing_trailing_newline() {
        // Given
        let fileHeader = "Some template\n"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(templateMacros.fileHeader == " Some template")
    }

    @Test func inserting_leading_space() {
        // Given
        let fileHeader = "Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(templateMacros.fileHeader == " Some template")
    }

    @Test func not_inserting_leading_space_if_already_present() {
        // Given
        let fileHeader = " Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(templateMacros.fileHeader == " Some template")
    }

    @Test func not_inserting_leading_space_if_starting_with_newline() {
        // Given
        let fileHeader = "\nSome template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(templateMacros.fileHeader == "\nSome template")
    }
}
