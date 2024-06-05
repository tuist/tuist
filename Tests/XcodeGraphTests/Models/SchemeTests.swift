import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class SchemeTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Scheme.test(name: "name", shared: true)

        // Then
        XCTAssertCodable(subject)
    }
}
