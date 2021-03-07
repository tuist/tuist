import Foundation
import TSCBasic
import TuistGenerator
import TuistGraph
import TuistSupportTesting
import XCTest

final class IDETemplateMacrosMapperTests: XCTestCase {
    var subject: IDETemplateMacrosMapper!

    override func setUp() {
        super.setUp()

        subject = IDETemplateMacrosMapper()
    }

    override func tearDown() {
        super.tearDown()
        
        subject = nil
    }

    func test_map_template_macros_creates_macros_plist() throws {
        // Given
        let templateMacros = IDETemplateMacros.test()
        let project = Project.test(ideTemplateMacros: templateMacros)

        // When
        let (got, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got, project)

        XCTAssertEqual(sideEffects, [
            .file(
                .init(
                    path: project.xcodeProjPath.appending(RelativePath("xcshareddata/IDETemplateMacros.plist")),
                    contents: try PropertyListEncoder().encode(templateMacros),
                    state: .present
                )
            ),
        ])
    }

    func test_map_empty_template_macros() throws {
        // Given
        let project = Project.empty()

        // When
        let (got, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got, project)
        XCTAssertEmpty(sideEffects)
    }
}
