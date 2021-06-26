import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ThirdPartyDependencyTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = ThirdPartyDependency.testXCFramework()

        // Then
        XCTAssertCodable(subject)
    }
}
