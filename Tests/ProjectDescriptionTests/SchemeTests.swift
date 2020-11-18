import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class SchemeTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable() throws {
        // Given
        let buildAction = [ExecutionAction(title: "Run Script", scriptText: "echo build_action", target: TargetReference(projectPath: nil, target: "target"))]
        let testAction = [ExecutionAction(title: "Run Script", scriptText: "echo test_action", target: TargetReference(projectPath: nil, target: "target"))]

        let subject = Scheme(name: "scheme",
                             shared: true,
                             buildAction: BuildAction(targets: [.init(projectPath: nil, target: "target")],
                                                      preActions: buildAction,
                                                      postActions: buildAction),
                             testAction: TestAction(targets: [.init(target: .init(projectPath: nil, target: "target"))],
                                                    arguments: Arguments(environment: ["test": "b"],
                                                                         launchArguments: [LaunchArgument(name: "test", isEnabled: true)]),
                                                    config: .debug,
                                                    coverage: true,
                                                    preActions: testAction,
                                                    postActions: testAction),
                             runAction: RunAction(config: .debug,
                                                  executable: .init(projectPath: nil, target: "executable"),
                                                  arguments: Arguments(environment: ["run": "b"],
                                                                       launchArguments: [LaunchArgument(name: "run", isEnabled: true)])))

        // When
        let encoded = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(Scheme.self, from: encoded)
        XCTAssertEqual(decoded, subject)
    }

    func test_defaultConfigurationNames() throws {
        // Given / When
        let buildAction = [ExecutionAction(title: "Run Script", scriptText: "echo build_action", target: .init(projectPath: nil, target: "target"))]
        let testAction = [ExecutionAction(title: "Run Script", scriptText: "echo test_action", target: .init(projectPath: nil, target: "target"))]

        let subject = Scheme(name: "scheme",
                             shared: true,
                             buildAction: BuildAction(targets: [.init(projectPath: nil, target: "target")],
                                                      preActions: buildAction,
                                                      postActions: buildAction),
                             testAction: TestAction(targets: [.init(target: .init(projectPath: nil, target: "target"))],
                                                    arguments: Arguments(environment: ["test": "b"],
                                                                         launchArguments: [LaunchArgument(name: "test", isEnabled: true)]),
                                                    config: .debug,
                                                    coverage: true,
                                                    preActions: testAction,
                                                    postActions: testAction),
                             runAction: RunAction(config: .release,
                                                  executable: .init(projectPath: nil, target: "executable"),
                                                  arguments: Arguments(environment: ["run": "b"],
                                                                       launchArguments: [LaunchArgument(name: "run", isEnabled: true)])))

        // Then
        XCTAssertEqual(subject.runAction?.configurationName, "Release")
        XCTAssertEqual(subject.testAction?.configurationName, "Debug")
    }
}
