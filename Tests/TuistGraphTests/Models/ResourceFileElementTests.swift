import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ResourceFileElementTests: TuistUnitTestCase {
    func test_codable_file() {
        // Given
        let subject = ResourceFileElement.file(
            path: "/path/to/element",
            tags: [
                "tag",
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_folderReference() {
        // Given
        let subject = ResourceFileElement.folderReference(
            path: "/path/to/folder",
            tags: [
                "tag",
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
