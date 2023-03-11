import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class BuildRuleCompilerSpecTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = BuildRule.CompilerSpec.customScript

        // Then
        XCTAssertCodable(subject)
    }
}
