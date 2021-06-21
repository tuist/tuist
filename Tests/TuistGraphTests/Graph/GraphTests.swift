import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class GraphTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Graph.test(name: "name", path: "/path/to")

        // Then
        XCTAssertCodable(subject)
    }
}
