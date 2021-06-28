import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ExternalDependencyTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = ExternalDependency.testXCFramework()

        // Then
        XCTAssertCodable(subject)
    }
}
