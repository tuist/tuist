import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class SchemeTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable() throws {
        // Given
        let subject = Scheme(
            name: "scheme",
            shared: true,
            buildAction: BuildAction(
                targets: [.init(projectPath: nil, target: "target")],
                preActions: mockExecutionAction("build_action"),
                postActions: mockExecutionAction("build_action")
            ),
            testAction: TestAction.targets(
                [TestableTarget(target: .init(projectPath: nil, target: "target"))],
                arguments: Arguments(
                    environment: ["test": "b"],
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
                    environment: ["run": "b"],
                    launchArguments: [LaunchArgument(name: "run", isEnabled: true)]
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
        let subject = Scheme(
            name: "scheme",
            shared: true,
            buildAction: BuildAction(
                targets: [.init(projectPath: nil, target: "target")],
                preActions: mockExecutionAction("build_action"),
                postActions: mockExecutionAction("build_action")
            ),
            testAction: TestAction.targets(
                [.init(target: .init(projectPath: nil, target: "target"))],
                arguments: Arguments(
                    environment: ["test": "b"],
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
                    environment: ["run": "b"],
                    launchArguments: [LaunchArgument(name: "run", isEnabled: true)]
                )
            )
        )

        // Then
        XCTAssertEqual(subject.runAction?.configuration.rawValue, "Release")
        XCTAssertEqual(subject.testAction?.configuration.rawValue, "Debug")
    }

    // MARK: - Helpers

    private func mockExecutionAction(_ actionName: String) -> [ExecutionAction] {
        [
            ExecutionAction(
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
