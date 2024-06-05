import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class BuildRuleTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = BuildRule(
            compilerSpec: .unifdef,
            fileType: .sourceFilesWithNamesMatching
        )

        // Then
        XCTAssertCodable(subject)
    }
}
