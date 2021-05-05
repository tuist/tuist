import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

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
