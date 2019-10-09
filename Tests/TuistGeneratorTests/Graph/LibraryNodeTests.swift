import Basic
import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistGenerator

final class LibraryNodeTests: TuistUnitTestCase {
    var subject: LibraryNode!
    var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        path = AbsolutePath("/test.a")
        subject = LibraryNode(path: path, publicHeaders: AbsolutePath("/headers"))
    }

    override func tearDown() {
        subject = nil
        path = nil
        super.tearDown()
    }

    func test_name() {
        XCTAssertEqual(subject.name, "test")
    }

    func test_binaryPath() {
        XCTAssertEqual(subject.binaryPath.pathString, "/test.a")
    }

    func test_architectures() throws {
        system.succeedCommand("/usr/bin/lipo", "-info", "/test.a", output: "Non-fat file: path is architecture: x86_64")
        try XCTAssertEqual(subject.architectures().first, .x8664)
    }

    func test_linking() {
        system.succeedCommand("/usr/bin/file", "/test.a", output: "whatever dynamically linked")
        try XCTAssertEqual(subject.linking(), .dynamic)
    }

    func test_equality() {
        // Given
        let a1 = LibraryNode(path: "/a", publicHeaders: "/a/header", swiftModuleMap: "/a/swiftmodulemap")
        let a2 = LibraryNode(path: "/a", publicHeaders: "/a/header/2", swiftModuleMap: "/a/swiftmodulemap")
        let b = LibraryNode(path: "/b", publicHeaders: "/b/header", swiftModuleMap: "/b/swiftmodulemap")

        // When / Then
        XCTAssertEqual(a1, a1)
        XCTAssertNotEqual(a1, a2)
        XCTAssertNotEqual(a2, b)
        XCTAssertNotEqual(a1, b)
    }

    func test_encode() {
        // Given
        System.shared = System()
        let library = LibraryNode(path: fixturePath(path: RelativePath("libStaticLibrary.a")),
                                  publicHeaders: fixturePath(path: RelativePath("")))
        let expected = """
        {
        "type": "precompiled",
        "path" : "\(library.path)",
        "architectures" : [
        "x86_64"
        ],
        "name" : "\(library.name)",
        "product" : "static_library"
        }
        """

        // Then
        XCTAssertEncodableEqualToJson(library, expected)
    }
}
