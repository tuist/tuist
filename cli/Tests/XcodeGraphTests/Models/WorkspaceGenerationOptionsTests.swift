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
}
