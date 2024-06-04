import Foundation
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class TargetReferenceTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = TargetReference(
            projectPath: "/path/to/project",
            name: "name"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
