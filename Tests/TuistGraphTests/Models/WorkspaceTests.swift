import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class WorkspaceTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = Workspace.test(
            path: "/path/to/workspace",
            name: "name"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
