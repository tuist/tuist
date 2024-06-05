import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class ExecutionActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = ExecutionAction(
            title: "title",
            scriptText: "text",
            target: .init(
                projectPath: "/path/to/project",
                name: "name"
            ),
            shellPath: nil,
            showEnvVarsInLog: false
        )

        // Then
        XCTAssertCodable(subject)
    }
}
