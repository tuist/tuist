import Foundation
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class AnalyzeActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = AnalyzeAction(configurationName: "name")

        // Then
        XCTAssertCodable(subject)
    }
}
