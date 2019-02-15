import Basic
@testable import TuistGenerator
import XCTest

final class GeneratorTests: XCTestCase {
    
    func test_generator_generateProject() throws {
        // Given
        let subject = Generator()
        let workspacePath = AbsolutePath("/tmp/some/directory")
        
        // When / Then
        XCTAssertThrowsError(try subject.generateProject(at: workspacePath)) {
            XCTAssertEqual($0 as? GeneratorError, .notImplemented)
        }
    }
    
    func test_generator_generateWorkspace() throws {
        // Given
        let subject = Generator()
        let workspacePath = AbsolutePath("/tmp/some/directory")

        // When / Then
        XCTAssertThrowsError(try subject.generateWorkspace(at: workspacePath)) {
            XCTAssertEqual($0 as? GeneratorError, .notImplemented)
        }
    }
    
    func test_generatorError_type() {
        XCTAssertEqual(GeneratorError.notImplemented.type, .abort)
    }
    
    func test_generatorError_description() {
        XCTAssertEqual(GeneratorError.notImplemented.description, "This feature is not yet implemented")
    }
}
