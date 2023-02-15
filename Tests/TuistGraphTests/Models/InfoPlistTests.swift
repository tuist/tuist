import Foundation
import TSCBasic
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class InfoPlistTests: XCTestCase {
    func test_codable_file() {
        // Given
        let subject = InfoPlist.file(path: "/path/to/file")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_dictionary() {
        // Given
        let subject = InfoPlist.dictionary([
            "key1": "value1",
            "key2": "value2",
            "key3": "value3",
        ])

        // Then
        XCTAssertCodable(subject)
    }

    func test_path_when_file() {
        // Given
        let path = try! AbsolutePath(validating: "/path/Info.list")
        let subject: InfoPlist = .file(path: path)

        // Then
        XCTAssertEqual(subject.path, path)
    }

    func test_expressive_by_string_literal() {
        // Given
        let subject: InfoPlist = "/path/Info.list"

        // Then
        XCTAssertEqual(subject.path, try AbsolutePath(validating: "/path/Info.list"))
    }
}
