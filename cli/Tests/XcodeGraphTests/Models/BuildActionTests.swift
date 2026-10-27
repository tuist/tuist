import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class BuildActionTests: XCTestCase {
    func test_codable() throws {
        // Given
        let subject = BuildAction(
            targets: [
                .init(
                    projectPath: try AbsolutePath(validating: "/path/to/project"),
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
