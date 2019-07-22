import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class SchemeTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable() throws {
        // Given
        let buildAction = [ExecutionAction(title: "Run Script", scriptText: "echo build_action", target: "target")]
        let testAction = [ExecutionAction(title: "Run Script", scriptText: "echo test_action", target: "target")]

        let subject = Scheme(name: "scheme",
                             shared: true,
                             buildAction: BuildAction(targets: ["target"],
                                                      preActions: buildAction,
                                                      postActions: buildAction),
                             testAction: TestAction(targets: ["target"],
                                                    arguments: Arguments(environment: ["test": "b"],
                                                                         launch: ["test": true]),
                                                    config: .debug,
                                                    coverage: true,
                                                    preActions: testAction,
                                                    postActions: testAction),
                             runAction: RunAction(config: .debug,
                                                  executable: "executable",
                                                  arguments: Arguments(environment: ["run": "b"],
                                                                       launch: ["run": true])))

        // When
        let encoded = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(Scheme.self, from: encoded)
        XCTAssertEqual(decoded, subject)
    }

    func test_defaultConfigurationNames() throws {
        // Given / When
        let buildAction = [ExecutionAction(title: "Run Script", scriptText: "echo build_action", target: "target")]
        let testAction = [ExecutionAction(title: "Run Script", scriptText: "echo test_action", target: "target")]

        let subject = Scheme(name: "scheme",
                             shared: true,
                             buildAction: BuildAction(targets: ["target"],
                                                      preActions: buildAction,
                                                      postActions: buildAction),
                             testAction: TestAction(targets: ["target"],
                                                    arguments: Arguments(environment: ["test": "b"],
                                                                         launch: ["test": true]),
                                                    config: .debug,
                                                    coverage: true,
                                                    preActions: testAction,
                                                    postActions: testAction),
                             runAction: RunAction(config: .release,
                                                  executable: "executable",
                                                  arguments: Arguments(environment: ["run": "b"],
                                                                       launch: ["run": true])))

        // Then
        XCTAssertEqual(subject.runAction?.configurationName, "Release")
        XCTAssertEqual(subject.testAction?.configurationName, "Debug")
    }
}
