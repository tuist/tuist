import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class RunActionTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = RunAction(
            configurationName: "name",
            attachDebugger: true,
            customLLDBInitFile: "/path/to/project",
            executable: .init(
                projectPath: "/path/to/project",
                name: "name"
            ),
            filePath: "/path/to/file",
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
            )
        )

        // Then
        XCTAssertCodable(subject)
    }
}
