import Basic
import Foundation
@testable import TuistGenerator

extension Arguments {
    static func test(environment: [String: String] = [:],
                     launch: [String: Bool] = [:]) -> Arguments {
        return Arguments(environment: environment,
                         launch: launch)
    }
}

extension RunAction {
    static func test(config: BuildConfiguration = .debug,
                     executable: String? = "Test",
                     arguments: Arguments? = Arguments.test()) -> RunAction {
        return RunAction(config: config,
                         executable: executable,
                         arguments: arguments)
    }
}

extension TestAction {
    static func test(targets: [String] = ["TestTests"],
                     arguments: Arguments? = Arguments.test(),
                     config: BuildConfiguration = .debug,
                     coverage: Bool = false) -> TestAction {
        return TestAction(targets: targets,
                          arguments: arguments,
                          config: config,
                          coverage: coverage)
    }
}

extension BuildAction {
    static func test(targets: [String] = ["Test"]) -> BuildAction {
        return BuildAction(targets: targets)
    }
}

extension Scheme {
    static func test(name: String = "Test",
                     shared: Bool = false,
                     buildAction: BuildAction? = BuildAction.test(),
                     testAction: TestAction? = TestAction.test(),
                     runAction: RunAction? = RunAction.test()) -> Scheme {
        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction)
    }
}
