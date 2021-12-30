import Foundation
import XCTest

@testable import ProjectDescription
@testable import TuistSupportTesting

final class CompatibleXcodeVersionsTests: XCTestCase {
    func test_codable_when_all() {
        // Given
        let subject = CompatibleXcodeVersions.all

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_when_list() {
        // Given
        let subject = CompatibleXcodeVersions.list(["10.3"])

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_when_exact() {
        // Given
        let subject = CompatibleXcodeVersions.exact("13.2.1")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_when_upToNext() {
        // Given
        let subject = CompatibleXcodeVersions.upToNextMajor("13.2")
        let subject2 = CompatibleXcodeVersions.upToNextMinor("13.2")

        // Then
        XCTAssertCodable(subject)
        XCTAssertCodable(subject2)
    }
}
