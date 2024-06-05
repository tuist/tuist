import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class TestActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = TestAction.test()

        // Then
        XCTAssertCodable(subject)
    }
}
