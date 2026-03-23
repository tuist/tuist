import XcodeGraph
import Testing

struct IDETemplateMacrosTests {
    @Test func test_removing_leading_comment_slashes() {
        // Given
        let fileHeader = "// Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(" Some template" == templateMacros.fileHeader)
    }

    @Test func test_space_preservation_if_leading_comment_slashes_are_present() {
        // Given
        let fileHeader = "//Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect("Some template" == templateMacros.fileHeader)
    }

    @Test func test_removing_trailing_newline() {
        // Given
        let fileHeader = "Some template\n"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(" Some template" == templateMacros.fileHeader)
    }

    @Test func test_inserting_leading_space() {
        // Given
        let fileHeader = "Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(" Some template" == templateMacros.fileHeader)
    }

    @Test func test_not_inserting_leading_space_if_already_present() {
        // Given
        let fileHeader = " Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect(" Some template" == templateMacros.fileHeader)
    }

    @Test func test_not_inserting_leading_space_if_starting_with_newline() {
        // Given
        let fileHeader = "\nSome template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        #expect("\nSome template" == templateMacros.fileHeader)
    }
}
