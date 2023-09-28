import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

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
