import Foundation
import XCTest
@testable import XcodeGraph

final class BuildRuleCompilerSpecTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = BuildRule.CompilerSpec.customScript

        // Then
        XCTAssertCodable(subject)
    }
}
