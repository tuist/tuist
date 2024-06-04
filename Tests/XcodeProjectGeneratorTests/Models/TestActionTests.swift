import Foundation
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class TestActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = TestAction.test()

        // Then
        XCTAssertCodable(subject)
    }
}
