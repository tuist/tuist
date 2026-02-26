import Foundation
import XCTest
@testable import XcodeGraph

final class BuildRuleFileTypeTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = BuildRule.FileType.sourceFilesWithNamesMatching

        // Then
        XCTAssertCodable(subject)
    }
}
