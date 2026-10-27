import Foundation
import XCTest
@testable import XcodeGraph

final class BuildRuleTests: XCTestCase {
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
