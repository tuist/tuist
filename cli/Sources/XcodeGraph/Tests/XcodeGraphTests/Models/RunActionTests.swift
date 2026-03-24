import Foundation
import Path
import Testing
@testable import XcodeGraph

struct RunActionTests {
    @Test func codable() throws {
        // Given
        let subject = RunAction(
            configurationName: "name",
            attachDebugger: true,
            customLLDBInitFile: try AbsolutePath(validating: "/path/to/project"),
            executable: .init(
                projectPath: try AbsolutePath(validating: "/path/to/project"),
                name: "name"
            ),
            filePath: try AbsolutePath(validating: "/path/to/file"),
            arguments: .init(
                environmentVariables: [
                    "key": EnvironmentVariable(value: "value", isEnabled: true),
                ],
                launchArguments: [
                    .init(
                        name: "name",
                        isEnabled: true
                    ),
                ]
            ),
            options: .init(),
            diagnosticsOptions: SchemeDiagnosticsOptions(
                mainThreadCheckerEnabled: true,
                performanceAntipatternCheckerEnabled: true
            ),
            askForAppToLaunch: true,
            appClipInvocationURL: URL(string: "https://app-clips-url.com/example")
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(RunAction.self, from: data)
        #expect(subject == decoded)
    }
}
