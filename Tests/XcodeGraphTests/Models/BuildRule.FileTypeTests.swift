import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class BuildRuleFileTypeTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = BuildRule.FileType.sourceFilesWithNamesMatching

        // Then
        XCTAssertCodable(subject)
    }
}
