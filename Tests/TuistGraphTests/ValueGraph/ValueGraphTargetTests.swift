import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ValueGraphTargetTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ValueGraphTarget.test()

        // Then
        XCTAssertCodable(subject)
    }
}
