import Foundation
import TSCBasic
import XCTest
@testable import TuistGraph
@testable import TuistSupportTesting

final class InfoPlistTests: XCTestCase {
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
