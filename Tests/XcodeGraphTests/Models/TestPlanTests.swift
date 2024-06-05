import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class TestPlanTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = TestPlan(
            path: "/path/to",
            testTargets: [],
            isDefault: true
        )

        // Then
        XCTAssertCodable(subject)
    }
}
