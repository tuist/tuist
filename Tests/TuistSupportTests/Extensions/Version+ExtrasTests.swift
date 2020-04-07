import Basic
import Foundation
import SPMUtility
import XCTest

@testable import TuistSupport

final class VersionExtrasTests: XCTestCase {
    func test_swiftVersion_when_patchComponentIsMissing() {
        // Given
        let version = "5.2"

        // When
        let got = Version.swiftVersion(version)

        // Then
        XCTAssertEqual(got.major, 5)
        XCTAssertEqual(got.minor, 2)
        XCTAssertEqual(got.patch, 0)
    }
}
