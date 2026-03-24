import Foundation
import Testing

@testable import ProjectDescription

struct SchemeTests {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    @Test func codable() throws {
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
                    language: "en",
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
        #expect(decoded == subject)
    }

    @Test func defaultConfigurationNames() throws {
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
                    language: "en",
                    region: "US",
                    storeKitConfigurationPath: nil,
                    simulatedLocation: nil,
                    enableGPUFrameCaptureMode: .autoEnabled
                )
            )
        )

        // Then
        #expect(subject.runAction?.configuration.rawValue == "Release")
        #expect(subject.testAction?.configuration.rawValue == "Debug")
        #expect(subject.runAction?.options.language == "en")
        #expect(subject.runAction?.options.region == "US")
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
