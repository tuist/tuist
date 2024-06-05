import Foundation
import TuistSupport
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class DependenciesGraphTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = DependenciesGraph.test()

        // Then
        XCTAssertCodable(subject)
    }
}
