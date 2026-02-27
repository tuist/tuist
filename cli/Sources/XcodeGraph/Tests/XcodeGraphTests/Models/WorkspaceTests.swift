import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class WorkspaceTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = Workspace.test(
            path: try AbsolutePath(validating: "/path/to/workspace"),
            name: "name"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
