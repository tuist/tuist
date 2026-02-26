import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class ResourceFileElementTests: XCTestCase {
    func test_codable_file() throws {
        // Given
        let subject = ResourceFileElement.file(
            path: try AbsolutePath(validating: "/path/to/element"),
            tags: [
                "tag",
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_folderReference() throws {
        // Given
        let subject = ResourceFileElement.folderReference(
            path: try AbsolutePath(validating: "/path/to/folder"),
            tags: [
                "tag",
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
