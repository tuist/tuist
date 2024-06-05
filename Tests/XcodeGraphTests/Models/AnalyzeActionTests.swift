import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class AnalyzeActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = AnalyzeAction(configurationName: "name")

        // Then
        XCTAssertCodable(subject)
    }
}
