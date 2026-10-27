import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class GraphTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = Graph.test(name: "name", path: try AbsolutePath(validating: "/path/to"))

        // Then
        XCTAssertCodable(subject)
    }
}
