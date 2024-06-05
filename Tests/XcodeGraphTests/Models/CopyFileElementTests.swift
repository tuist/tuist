import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class CopyFileElementTests: TuistUnitTestCase {
    func test_codable_file() {
        // Given
        let subject = CopyFileElement.file(path: "/path/to/file", condition: .when([.macos]))

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_folderReference() {
        // Given
        let subject = CopyFileElement.folderReference(path: "/folder/reference", condition: .when([.macos]))

        // Then
        XCTAssertCodable(subject)
    }
}
