import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class RequirementTests: TuistUnitTestCase {
    func test_codable_range() {
        // Given
        let subject = Requirement.range(from: "1.0.0", to: "2.0.0")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_upToNextMajor() {
        // Given
        let subject = Requirement.upToNextMajor("1.2.3")

        // Then
        XCTAssertCodable(subject)
    }
}
