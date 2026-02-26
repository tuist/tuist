import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class TargetReferenceTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = TargetReference(
            projectPath: try AbsolutePath(validating: "/path/to/project"),
            name: "name"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
