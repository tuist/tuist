import Foundation
import Path
import XCTest

@testable import TuistSupport
@testable import TuistTesting

final class AbsolutePathExtrasTests: TuistUnitTestCase {
    func test_commonAncestor_siblings() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/path/to/B")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        XCTAssertEqual(result, try AbsolutePath(validating: "/path/to"))
    }

    func test_commonAncestor_parent() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/path/to/")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        XCTAssertEqual(result, try AbsolutePath(validating: "/path/to"))
    }

    func test_commonAncestor_none() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/another/path")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        XCTAssertEqual(result, try AbsolutePath(validating: "/"))
    }

    func test_commonAncestor_commutative() {
        // Given
        let pathA = try! AbsolutePath(validating: "/path/to/A")
        let pathB = try! AbsolutePath(validating: "/path/to/B")

        // When
        let resultA = pathA.commonAncestor(with: pathB)
        let resultB = pathB.commonAncestor(with: pathA)

        // Then
        XCTAssertEqual(resultA, resultB)
    }

    func test_isInOpaqueDirectory() throws {
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.bundle").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.xcassets").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.xcassets").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.scnassets").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.xcdatamodeld").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.docc").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.playground").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.bundle").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.xcmappingmodel").isInOpaqueDirectory)

        XCTAssertFalse(try AbsolutePath(validating: "/").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.notopaque/file.notopaque").isInOpaqueDirectory)
        XCTAssertFalse(try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle/file.png").isInOpaqueDirectory)

        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.bundle/file.png").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.xcassets/file.png").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.xcassets/file.png").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.scnassets/file.png").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.xcdatamodeld/file.png").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.docc/file.png").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.playground/file.png").isInOpaqueDirectory)
        XCTAssertTrue(try AbsolutePath(validating: "/test/directory.xcmappingmodel/file.png").isInOpaqueDirectory)
    }

    func test_opaqueDirectory() async throws {
        for directory in [
            "/test/directory.bundle",
            "/test/directory.xcassets",
            "/test/directory.scnassets",
            "/test/directory.xcdatamodeld",
            "/test/directory.docc",
            "/test/directory.xcmappingmodel",
        ] as [AbsolutePath] {
            XCTAssertEqual(directory.opaqueParentDirectory(), nil)
        }

        XCTAssertEqual(try AbsolutePath(validating: "/").opaqueParentDirectory(), nil)
        XCTAssertEqual(try AbsolutePath(validating: "/test/directory.notopaque/file.notopaque").opaqueParentDirectory(), nil)
        XCTAssertEqual(try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle").opaqueParentDirectory(), nil)
        XCTAssertEqual(
            try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle/file.png").opaqueParentDirectory(),
            try AbsolutePath(validating: "/test/directory.notopaque/directory.bundle")
        )

        for file in [
            "/test/directory.bundle/file.png",
            "/test/directory.xcassets/file.png",
            "/test/directory.scnassets/file.png",
            "/test/directory.xcdatamodeld/file.png",
            "/test/directory.docc/file.png",
            "/test/directory.xcmappingmodel/file.png",
        ] as [AbsolutePath] {
            XCTAssertEqual(file.opaqueParentDirectory(), file.parentDirectory)
        }
    }
}
