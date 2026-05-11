import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class InfoPlistTests: XCTestCase {
    func test_codable_file() throws {
        // Given
        let subject = InfoPlist.file(path: try AbsolutePath(validating: "/path/to/file"))

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

    func test_path_when_file() throws {
        // Given
        let path = try AbsolutePath(validating: "/path/Info.list")
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

    func test_expressive_by_string_literal_using_build_variable() {
        // Given
        let subject1: InfoPlist = "$(CONFIGURATION)/Info.list"
        let subject2: InfoPlist = "${CONFIGURATION}/Info.list"

        // Then
        XCTAssertEqual(subject1, .variable("$(CONFIGURATION)/Info.list", configuration: nil))
        XCTAssertEqual(subject2, .variable("${CONFIGURATION}/Info.list", configuration: nil))
    }
}
