import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class TestPlanTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = TestPlan(
            path: try AbsolutePath(validating: "/path/to"),
            testTargets: [],
            isDefault: true
        )

        // Then
        XCTAssertCodable(subject)
    }
}
