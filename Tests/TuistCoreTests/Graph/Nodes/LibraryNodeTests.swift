import Foundation
import TSCBasic
import XCTest

@testable import TuistCore
@testable import TuistSupport
@testable import TuistSupportTesting

final class LibraryNodeTests: TuistUnitTestCase {
    var subject: LibraryNode!
    var path: AbsolutePath!

    override func setUp() {
        super.setUp()
        path = AbsolutePath("/test.a")
        subject = LibraryNode(path: path, publicHeaders: AbsolutePath("/headers"), architectures: [.arm64], linking: .static)
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

    func test_equality() {
        // Given
        let a1 = LibraryNode(
            path: "/a",
            publicHeaders: "/a/header",
            architectures: [.arm64],
            linking: .static,
            swiftModuleMap: "/a/swiftmodulemap"
        )
        let a2 = LibraryNode(
            path: "/a",
            publicHeaders: "/a/header/2",
            architectures: [.arm64],
            linking: .static,
            swiftModuleMap: "/a/swiftmodulemap"
        )
        let b = LibraryNode(
            path: "/b",
            publicHeaders: "/b/header",
            architectures: [.arm64],
            linking: .static,
            swiftModuleMap: "/b/swiftmodulemap"
        )

        // When / Then
        XCTAssertEqual(a1, a1)
        XCTAssertNotEqual(a1, a2)
        XCTAssertNotEqual(a2, b)
        XCTAssertNotEqual(a1, b)
    }

    func test_encode() {
        // Given
        System.shared = System()
        let library = LibraryNode(
            path: fixturePath(path: RelativePath("libStaticLibrary.a")),
            publicHeaders: fixturePath(path: RelativePath("")),
            architectures: [.arm64],
            linking: .static
        )
        let expected = """
        {
        "type": "precompiled",
        "path" : "\(library.path.pathString)",
        "architectures" : [
        "arm64"
        ],
        "name" : "\(library.name)",
        "product" : "static_library"
        }
        """

        // Then
        XCTAssertEncodableEqualToJson(library, expected)
    }

    func test_product_when_static() {
        // Given
        let subject = LibraryNode.test(linking: .static)

        // When
        let got = subject.product

        // Then
        XCTAssertEqual(got, .staticLibrary)
    }

    func test_product_when_dynamic() {
        // Given
        let subject = LibraryNode.test(linking: .dynamic)

        // When
        let got = subject.product

        // Then
        XCTAssertEqual(got, .dynamicLibrary)
    }
}
