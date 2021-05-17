import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class DependenciesGraphDependencyTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = DependenciesGraphDependency.testXCFramework()

        // Then
        XCTAssertCodable(subject)
    }
}
