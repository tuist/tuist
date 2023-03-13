import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class BuildRuleFileTypeTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = BuildRule.FileType.sourceFilesWithNamesMatching

        // Then
        XCTAssertCodable(subject)
    }
}
