import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class BuildActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = BuildAction(
            targets: [
                .init(
                    projectPath: "/path/to/project",
                    name: "name"
                ),
            ],
            preActions: [
                .init(
                    title: "preActionTitle",
                    scriptText: "text",
                    target: nil,
                    shellPath: nil,
                    showEnvVarsInLog: true
                ),
            ],
            postActions: [
                .init(
                    title: "postActionTitle",
                    scriptText: "text",
                    target: nil,
                    shellPath: nil,
                    showEnvVarsInLog: false
                ),
            ]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
