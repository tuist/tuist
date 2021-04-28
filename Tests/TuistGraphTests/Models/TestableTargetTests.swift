import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class TestableTargetTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = TestableTarget(
            target: .init(
                projectPath: "/path/to/project",
                name: "name"
            ),
            skipped: true,
            parallelizable: true,
            randomExecutionOrdering: true
        )

        // Then
        XCTAssertCodable(subject)
    }
}
