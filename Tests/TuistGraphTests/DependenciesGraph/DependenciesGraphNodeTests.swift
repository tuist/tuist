import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class DependenciesGraphNodeTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = DependenciesGraphNode.testXCFramework()

        // Then
        XCTAssertCodable(subject)
    }
}
