import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class SchemeTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable() throws {
        // Given
        let subject: Scheme = .scheme(
            name: "scheme",
            shared: true,
            buildAction: .buildAction(
                targets: [.init(projectPath: nil, target: "target")],
                preActions: mockExecutionAction("build_action"),
                postActions: mockExecutionAction("build_action")
            ),
            testAction: TestAction.targets(
                [.testableTarget(target: .init(projectPath: nil, target: "target"))],
                arguments: Arguments(
                    environmentVariables: ["test": "b"],
                    launchArguments: [LaunchArgument(name: "test", isEnabled: true)]
                ),
                configuration: .debug,
                preActions: mockExecutionAction("test_action"),
                postActions: mockExecutionAction("test_action"),
                options: .options(coverage: true)
            ),
            runAction: RunAction(
                configuration: .debug,
                attachDebugger: true,
                preActions: mockExecutionAction("run_action"),
                postActions: mockExecutionAction("run_action"),
                executable: .init(projectPath: nil, target: "executable"),
                arguments: Arguments(
                    environmentVariables: ["run": "b"],
                    launchArguments: [LaunchArgument(name: "run", isEnabled: true)]
                ),
                options: RunActionOptions(
                    language: .init(identifier: "en"),
                    region: "US",
                    storeKitConfigurationPath: nil,
                    simulatedLocation: nil,
                    enableGPUFrameCaptureMode: .autoEnabled
                )
            )
        )

        // When
        let encoded = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(Scheme.self, from: encoded)
        XCTAssertEqual(decoded, subject)
    }

    func test_defaultConfigurationNames() throws {
        // Given / When
        let subject: Scheme = .scheme(
            name: "scheme",
            shared: true,
            buildAction: .buildAction(
                targets: [.target("target")],
                preActions: mockExecutionAction("build_action"),
                postActions: mockExecutionAction("build_action")
            ),
            testAction: TestAction.targets(
                [.testableTarget(target: .init(projectPath: nil, target: "target"))],
                arguments: Arguments(
                    environmentVariables: ["test": "b"],
                    launchArguments: [LaunchArgument(name: "test", isEnabled: true)]
                ),
                configuration: .debug,
                preActions: mockExecutionAction("test_action"),
                postActions: mockExecutionAction("test_action"),
                options: .options(coverage: true)
            ),
            runAction: RunAction(
                configuration: .release,
                attachDebugger: true,
                preActions: mockExecutionAction("run_action"),
                postActions: mockExecutionAction("run_action"),
                executable: .init(projectPath: nil, target: "executable"),
                arguments: Arguments(
                    environmentVariables: ["run": "b"],
                    launchArguments: [LaunchArgument(name: "run", isEnabled: true)]
                ),
                options: RunActionOptions(
                    language: .init(identifier: "en"),
                    region: "US",
                    storeKitConfigurationPath: nil,
                    simulatedLocation: nil,
                    enableGPUFrameCaptureMode: .autoEnabled
                )
            )
        )

        // Then
        XCTAssertEqual(subject.runAction?.configuration.rawValue, "Release")
        XCTAssertEqual(subject.testAction?.configuration.rawValue, "Debug")
        XCTAssertEqual(subject.runAction?.options.language, "en")
        XCTAssertEqual(subject.runAction?.options.region, "US")
    }

    // MARK: - Helpers

    private func mockExecutionAction(_ actionName: String) -> [ExecutionAction] {
        [
            .executionAction(
                title: "Run Script",
                scriptText: "echo \(actionName)",
                target: TargetReference(
                    projectPath: nil,
                    target: "target"
                ),
                shellPath: "/bin/sh"
            ),
        ]
    }
}
