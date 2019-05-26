import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class InfoPlistTests: XCTestCase {
    func test_equal() {
        // Given
        let first: InfoPlist = .file(path: AbsolutePath("/path/Info.list"))
        let second: InfoPlist = .file(path: AbsolutePath("/path/Info.list"))

        // Then
        XCTAssertEqual(first, second)
    }

    func test_path_when_file() {
        // Given
        let path = AbsolutePath("/path/Info.list")
        let subject: InfoPlist = .file(path: path)

        // Then
        XCTAssertEqual(subject.path, path)
    }

    func test_expressive_by_string_literal() {
        // Given
        let subject: InfoPlist = "/path/Info.list"

        // Then
        XCTAssertEqual(subject.path, AbsolutePath("/path/Info.list"))
    }
}
