import Foundation
import Path
import Testing
@testable import XcodeGraph

struct ExecutionActionTests {
    @Test func test_codable() throws {
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
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(ExecutionAction.self, from: data)
        #expect(subject == decoded)
    }
}
