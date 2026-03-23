import Foundation
import Path
import Testing
@testable import XcodeGraph

struct BuildActionTests {
    @Test func test_codable() throws {
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
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(BuildAction.self, from: data)
        #expect(subject == decoded)
    }
}
