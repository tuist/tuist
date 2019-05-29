import Basic
import Foundation
import XCTest

@testable import TuistGenerator

final class DerivedFileTests: XCTestCase {
    func test_path_when_infoPlist() {
        // Given
        let subject = DerivedFile.infoPlist(target: "Core")
        let sourceRootPath = AbsolutePath("/")

        // When
        let got = subject.path(sourceRootPath: sourceRootPath)

        // Then
        XCTAssertEqual(got, sourceRootPath.appending(RelativePath("Derived/InfoPlists/Core.plist")))
    }

    func test_infoPlistsPath() {
        // Given
        let sourceRootPath = AbsolutePath("/")

        // When
        let got = DerivedFile.infoPlistsPath(sourceRootPath: sourceRootPath)

        // Then
        XCTAssertEqual(got, sourceRootPath.appending(RelativePath("Derived/InfoPlists")))
    }
}
