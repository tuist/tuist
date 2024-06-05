import Foundation
import XCTest

@testable import XcodeProjectGenerator
@testable import TuistSupportTesting

final class SchemeTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Scheme.test(name: "name", shared: true)

        // Then
        XCTAssertCodable(subject)
    }
}
