import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class FileElementTests: TuistUnitTestCase {
    func test_codable_file() {
        // Given
        let subject = FileElement.file(path: "/path/to/file")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_folderReference() {
        // Given
        let subject = FileElement.folderReference(path: "/folder/reference")

        // Then
        XCTAssertCodable(subject)
    }
}
