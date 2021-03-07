import TuistGraph
import XCTest

final class IDETemplateMacrosTests: XCTestCase {
    func test_removing_leading_comment_slashes() {
        // Given
        let fileHeader = "// Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        XCTAssertEqual(" Some template", templateMacros.fileHeader)
    }

    func test_space_preservation_if_leading_comment_slashes_are_present() {
        // Given
        let fileHeader = "//Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        XCTAssertEqual("Some template", templateMacros.fileHeader)
    }

    func test_removing_trailing_newline() {
        // Given
        let fileHeader = "Some template\n"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        XCTAssertEqual(" Some template", templateMacros.fileHeader)
    }

    func test_inserting_leading_space() {
        // Given
        let fileHeader = "Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        XCTAssertEqual(" Some template", templateMacros.fileHeader)
    }

    func test_not_inserting_leading_space_if_already_present() {
        // Given
        let fileHeader = " Some template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        XCTAssertEqual(" Some template", templateMacros.fileHeader)
    }

    func test_not_inserting_leading_space_if_starting_with_newline() {
        // Given
        let fileHeader = "\nSome template"
        let templateMacros = IDETemplateMacros(fileHeader: fileHeader)

        // Then
        XCTAssertEqual("\nSome template", templateMacros.fileHeader)
    }
}
