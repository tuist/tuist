import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ValueGraphTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ValueGraph.test(name: "name", path: "/path/to")
        
        // Then
        XCTAssertCodable(subject)
    }
}
