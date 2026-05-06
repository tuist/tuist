import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class TestableTargetTests: XCTestCase {
    func test_codable_with_deprecated_parallelizable() throws {
        // Given
        let subject = TestableTarget.test(
            target: .init(
                projectPath: try AbsolutePath(validating: "/path/to/project"),
                name: "name"
            ),
            skipped: true,
            parallelizable: true,
            randomExecutionOrdering: true
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable() throws {
        // Given
        let subject = TestableTarget(
            target: .init(
                projectPath: try AbsolutePath(validating: "/path/to/project"),
                name: "name"
            ),
            skipped: true,
            parallelization: .all,
            randomExecutionOrdering: true
        )

        // Then
        XCTAssertCodable(subject)
    }
}
