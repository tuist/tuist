import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class BuildRuleCompilerSpecTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = BuildRule.CompilerSpec.customScript

        // Then
        XCTAssertCodable(subject)
    }
}
