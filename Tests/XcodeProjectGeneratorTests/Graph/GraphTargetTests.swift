import Foundation
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class GraphTargetTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = GraphTarget.test()

        // Then
        XCTAssertCodable(subject)
    }
}
