import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class RunActionTests: XCTestCase {
    func test_codable() throws {
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
        XCTAssertCodable(subject)
    }
}
