import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class GraphTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Graph.test(name: "name", path: "/path/to")

        // Then
        XCTAssertCodable(subject)
    }
}
