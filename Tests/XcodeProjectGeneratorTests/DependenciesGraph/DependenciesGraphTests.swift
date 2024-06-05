import Foundation
import TuistSupport
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class DependenciesGraphTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = DependenciesGraph.test()

        // Then
        XCTAssertCodable(subject)
    }
}
