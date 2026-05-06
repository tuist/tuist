import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class ExecutionActionTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = ExecutionAction(
            title: "title",
            scriptText: "text",
            target: .init(
                projectPath: try AbsolutePath(validating: "/path/to/project"),
                name: "name"
            ),
            shellPath: nil,
            showEnvVarsInLog: false
        )

        // Then
        XCTAssertCodable(subject)
    }
}
