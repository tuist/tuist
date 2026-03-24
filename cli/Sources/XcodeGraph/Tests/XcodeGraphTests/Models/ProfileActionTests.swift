import Foundation
import Path
import Testing
@testable import XcodeGraph

struct ProfileActionTests {
    @Test func codable() throws {
        // Given
        let subject = ProfileAction(
            configurationName: "name",
            executable: .init(
                projectPath: try AbsolutePath(validating: "/path/to/project"),
                name: "name"
            ),
            askForAppToLaunch: true,
            arguments: .init(
                environmentVariables: [
                    "key": EnvironmentVariable(value: "value", isEnabled: true),
                ],
                launchArguments: [
                    .init(
                        name: "name",
                        isEnabled: false
                    ),
                ]
            )
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(ProfileAction.self, from: data)
        #expect(subject == decoded)
    }
}
