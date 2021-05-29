import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class SourceFileTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = SourceFile(
            path: "/path/to/file",
            compilerFlags: "flag",
            contentHash: "hash"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
