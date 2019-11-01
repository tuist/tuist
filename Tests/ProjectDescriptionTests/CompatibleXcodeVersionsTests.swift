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
}
