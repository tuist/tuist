import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class SDKSourceTests: TuistUnitTestCase {
    func test_codable_developer() {
        // Given
        let subject = SDKSource.developer

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_system() {
        // Given
        let subject = SDKSource.system

        // Then
        XCTAssertCodable(subject)
    }
}
