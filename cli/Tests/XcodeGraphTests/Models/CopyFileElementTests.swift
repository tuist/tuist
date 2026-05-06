import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class CopyFileElementTests: XCTestCase {
    func test_codable_file() throws {
        // Given
        let subject = CopyFileElement.file(path: try AbsolutePath(validating: "/path/to/file"), condition: .when([.macos]))

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_folderReference() throws {
        // Given
        let subject = CopyFileElement.folderReference(
            path: try AbsolutePath(validating: "/folder/reference"),
            condition: .when([.macos])
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_buildProduct() throws {
        // Given
        let subject = CopyFileElement.buildProduct(
            name: "HelperApp",
            condition: .when([.macos]),
            codeSignOnCopy: true
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_buildProduct_isNotReference() {
        let subject = CopyFileElement.buildProduct(name: "HelperApp")
        XCTAssertFalse(subject.isReference)
    }

    func test_buildProduct_condition() {
        let subject = CopyFileElement.buildProduct(name: "HelperApp", condition: .when([.macos]))
        XCTAssertEqual(subject.condition, .when([.macos]))
    }

    func test_buildProduct_codeSignOnCopy() {
        let subject = CopyFileElement.buildProduct(name: "HelperApp", codeSignOnCopy: true)
        XCTAssertTrue(subject.codeSignOnCopy)
    }
}
