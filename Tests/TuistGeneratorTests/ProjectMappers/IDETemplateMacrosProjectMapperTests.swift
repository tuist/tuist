import Foundation
import TSCBasic
import TuistGraph
import TuistGenerator
import XCTest

final class IDETemplateMacrosProjectMapperTests: XCTestCase {
    var subject: IDETemplateMacrosProjectMapper!
    var templateMacros: IDETemplateMacros!
    
    override func setUp() {
        super.setUp()
        
        templateMacros = .init(fileHeader: .random())
        subject = IDETemplateMacrosProjectMapper(
            config: Config.test(generationOptions: [.templateMacros(templateMacros)])
        )
    }
    
    override func tearDown() {
        super.tearDown()
        subject = nil
        templateMacros = nil
    }
    
    func test_map_template_macros_creates_macros_plist() throws {
        // Given
        let project = Project.test()
        
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
            )
        ])
    }
    
    func test_map_empty_template_macros() throws {
        // Given
        let subject = IDETemplateMacrosProjectMapper(config: .test(generationOptions: []))
        let project = Project.test()
        
        // When
        let (got, sideEffects) = try subject.map(project: project)
        
        // Then
        XCTAssertEqual(got, project)
        XCTAssertEmpty(sideEffects)
    }
}
