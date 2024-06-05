import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class GraphTargetTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = GraphTarget.test()

        // Then
        XCTAssertCodable(subject)
    }
}
