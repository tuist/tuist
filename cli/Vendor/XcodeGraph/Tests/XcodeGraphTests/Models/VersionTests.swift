import Foundation
import XcodeGraph
import XCTest

final class VersionTests: XCTestCase {
    func test_xcodeStringValue() {
        // Given
        let version = Version(stringLiteral: "1.2.3")

        // When
        let got = version.xcodeStringValue

        // Then
        XCTAssertEqual(got, "123")
    }

    func test_codable() {
        // Given
        let version = Version(stringLiteral: "1.2.3")

        // Then
        XCTAssertCodable(version)
    }
}
