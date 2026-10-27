import Foundation
import XCTest
@testable import XcodeGraph

final class AnalyzeActionTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = AnalyzeAction(configurationName: "name")

        // Then
        XCTAssertCodable(subject)
    }
}
