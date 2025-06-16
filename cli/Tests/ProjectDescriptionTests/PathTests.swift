import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription
@testable import TuistSupportTesting

final class PathTests: TuistUnitTestCase {
    func test_codable_when_relativeToCurrentFile() {
        XCTAssertCodable(Path.relativeToCurrentFile("file.swift"))
    }

    func test_codable_when_relativeToManifest() {
        XCTAssertCodable(Path.relativeToManifest("file.swift"))
    }

    func test_codable_when_relativeToRoot() {
        XCTAssertCodable(Path.relativeToRoot("file.swift"))
    }

    func test_init_when_the_path_is_prefixed_with_two_slashes() {
        let path: Path = "//file.swift"
        XCTAssertEqual(path, Path.relativeToRoot("file.swift"))
    }

    func test_init_when_the_path_is_not_prefixed() {
        let path: Path = "file.swift"
        XCTAssertEqual(path, Path.relativeToManifest("file.swift"))
    }
}
