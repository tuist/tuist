import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class SourceFileTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = SourceFile(
            path: try AbsolutePath(validating: "/path/to/file"),
            compilerFlags: "flag",
            contentHash: "hash"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
