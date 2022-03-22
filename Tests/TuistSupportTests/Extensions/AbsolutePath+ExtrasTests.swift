import Foundation
import TSCBasic
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class AbsolutePathExtrasTests: TuistUnitTestCase {
    func test_commonAncestor_siblings() {
        // Given
        let pathA = AbsolutePath("/path/to/A")
        let pathB = AbsolutePath("/path/to/B")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        XCTAssertEqual(result, AbsolutePath("/path/to"))
    }

    func test_commonAncestor_parent() {
        // Given
        let pathA = AbsolutePath("/path/to/A")
        let pathB = AbsolutePath("/path/to/")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        XCTAssertEqual(result, AbsolutePath("/path/to"))
    }

    func test_commonAncestor_none() {
        // Given
        let pathA = AbsolutePath("/path/to/A")
        let pathB = AbsolutePath("/another/path")

        // When
        let result = pathA.commonAncestor(with: pathB)

        // Then
        XCTAssertEqual(result, AbsolutePath("/"))
    }

    func test_commonAncestor_commutative() {
        // Given
        let pathA = AbsolutePath("/path/to/A")
        let pathB = AbsolutePath("/path/to/B")

        // When
        let resultA = pathA.commonAncestor(with: pathB)
        let resultB = pathB.commonAncestor(with: pathA)

        // Then
        XCTAssertEqual(resultA, resultB)
    }

    func test_throwingGlob_throws_when_directoryDoesntExist() throws {
        // Given
        let dir = try temporaryPath()

        // Then
        XCTAssertThrowsSpecific(
            try dir.throwingGlob("invalid/path/**/*"),
            GlobError.nonExistentDirectory(InvalidGlob(
                pattern: dir.appending(RelativePath("invalid/path/**/*")).pathString,
                nonExistentPath: dir.appending(RelativePath("invalid/path/"))
            ))
        )
    }

    func test_isInOpaqueDirectory() throws {
        XCTAssertFalse(AbsolutePath("/test/directory.bundle").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.xcassets").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.xcassets").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.scnassets").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.xcdatamodeld").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.docc").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.playground").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.bundle").isInOpaqueDirectory)

        XCTAssertFalse(AbsolutePath("/").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.notopaque/file.notopaque").isInOpaqueDirectory)
        XCTAssertFalse(AbsolutePath("/test/directory.notopaque/directory.bundle").isInOpaqueDirectory)
        XCTAssertTrue(AbsolutePath("/test/directory.notopaque/directory.bundle/file.png").isInOpaqueDirectory)

        XCTAssertTrue(AbsolutePath("/test/directory.bundle/file.png").isInOpaqueDirectory)
        XCTAssertTrue(AbsolutePath("/test/directory.xcassets/file.png").isInOpaqueDirectory)
        XCTAssertTrue(AbsolutePath("/test/directory.xcassets/file.png").isInOpaqueDirectory)
        XCTAssertTrue(AbsolutePath("/test/directory.scnassets/file.png").isInOpaqueDirectory)
        XCTAssertTrue(AbsolutePath("/test/directory.xcdatamodeld/file.png").isInOpaqueDirectory)
        XCTAssertTrue(AbsolutePath("/test/directory.docc/file.png").isInOpaqueDirectory)
        XCTAssertTrue(AbsolutePath("/test/directory.playground/file.png").isInOpaqueDirectory)
    }
}
