import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class GraphDependencyTests: TuistUnitTestCase {
    func test_codable_target() {
        // Given
        let subject = GraphDependency.testTarget()

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_framework() {
        // Given
        let subject = GraphDependency.testFramework()

        // Then
        XCTAssertCodable(subject)
    }
}
