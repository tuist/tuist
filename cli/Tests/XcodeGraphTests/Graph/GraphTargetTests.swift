import Foundation
import XCTest
@testable import XcodeGraph

final class GraphTargetTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = GraphTarget.test()

        // Then
        XCTAssertCodable(subject)
    }
}
