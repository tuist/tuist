import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

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
            showEnvVarsInLog: false
        )

        // Then
        XCTAssertCodable(subject)
    }
}
