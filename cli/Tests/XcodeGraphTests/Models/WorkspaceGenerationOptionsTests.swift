import Foundation
import XCTest
@testable import XcodeGraph

final class WorkspaceGenerationOptionsTests: XCTestCase {
    func test_codable_whenDefault() {
        // Given
        let subject = Workspace.GenerationOptions.test()

        // Then
        XCTAssertCodable(subject)
    }

    func test_defaultProjectsOrderIsAlphabetical() {
        let subject = Workspace.GenerationOptions.test()

        XCTAssertEqual(subject.projectsOrder, .alphabetical)
    }

    func test_manifestProjectsOrderIsCodable() {
        let subject = Workspace.GenerationOptions.test(projectsOrder: .manifestOrder)

        XCTAssertCodable(subject)
        XCTAssertEqual(subject.projectsOrder, .manifestOrder)
    }
}
