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
}
