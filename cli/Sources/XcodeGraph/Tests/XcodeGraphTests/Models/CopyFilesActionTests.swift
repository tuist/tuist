import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class CopyFilesActionTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = CopyFilesAction(
            name: "name",
            destination: .frameworks,
            subpath: "subpath",
            files: [
                .file(path: try AbsolutePath(validating: "/path/to/file")),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
