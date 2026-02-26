import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class CoreDataModelTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = CoreDataModel(
            path: try AbsolutePath(validating: "/path/to/model"),
            versions: [
                try AbsolutePath(validating: "/path/to/version"),
            ],
            currentVersion: "1.1.1"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
