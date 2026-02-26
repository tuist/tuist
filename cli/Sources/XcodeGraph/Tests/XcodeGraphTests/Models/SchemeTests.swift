import Foundation
import XCTest
@testable import XcodeGraph

final class SchemeTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = Scheme.test(name: "name", shared: true)

        // Then
        XCTAssertCodable(subject)
    }
}
