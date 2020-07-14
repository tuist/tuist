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
        XCTAssertThrowsSpecific(try dir.throwingGlob("invalid/path/**/*"), GlobError.nonExistentDirectory(InvalidGlob(pattern: dir.appending(RelativePath("invalid/path/**/*")).pathString, nonExistentPath: dir.appending(RelativePath("invalid/path/")))))
    }
}
