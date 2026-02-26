import Foundation
import XCTest
@testable import XcodeGraph

final class TestActionTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = TestAction.test()

        // Then
        XCTAssertCodable(subject)
    }
}
