import Foundation
import XCTest
@testable import XcodeGraph

final class DependenciesGraphTests: XCTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = DependenciesGraph.test()

        // Then
        XCTAssertCodable(subject)
    }
}
