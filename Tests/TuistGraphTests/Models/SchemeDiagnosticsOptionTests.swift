import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class SchemeDiagnosticsOptionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = SchemeDiagnosticsOption.mainThreadChecker

        // Then
        XCTAssertCodable(subject)
    }
}
