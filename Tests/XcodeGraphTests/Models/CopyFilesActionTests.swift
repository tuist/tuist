import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class CopyFilesActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = CopyFilesAction(
            name: "name",
            destination: .frameworks,
            subpath: "subpath",
            files: [
                .file(path: "/path/to/file"),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
