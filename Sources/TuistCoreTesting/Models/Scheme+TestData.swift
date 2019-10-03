import Basic
import Foundation
@testable import TuistCore

public extension Arguments {
    static func test(environment: [String: String] = [:],
                     launch: [String: Bool] = [:]) -> Arguments {
        return Arguments(environment: environment,
                         launch: launch)
    }
}

public extension RunAction {
    static func test(configurationName: String = BuildConfiguration.debug.name,
                     executable: String? = "App",
                     arguments: Arguments? = Arguments.test()) -> RunAction {
        return RunAction(configurationName: configurationName,
                         executable: executable,
                         arguments: arguments)
    }
}

public extension TestAction {
    static func test(targets: [String] = ["AppTests"],
                     arguments: Arguments? = Arguments.test(),
                     configurationName: String = BuildConfiguration.debug.name,
                     coverage: Bool = false,
                     codeCoverageTargets: [String] = [],
                     preActions: [ExecutionAction] = [],
                     postActions: [ExecutionAction] = []) -> TestAction {
        return TestAction(targets: targets,
                          arguments: arguments,
                          configurationName: configurationName,
                          coverage: coverage,
                          codeCoverageTargets: codeCoverageTargets,
                          preActions: preActions,
                          postActions: postActions)
    }
}

public extension BuildAction {
    static func test(targets: [String] = ["App"],
                     preActions: [ExecutionAction] = [],
                     postActions: [ExecutionAction] = []) -> BuildAction {
        return BuildAction(targets: targets, preActions: preActions, postActions: postActions)
    }
}

public extension ArchiveAction {
    static func test(configurationName: String = "Beta Release",
                     revealArchiveInOrganizer: Bool = true,
                     customArchiveName: String? = nil,
                     preActions: [ExecutionAction] = [],
                     postActions: [ExecutionAction] = []) -> ArchiveAction {
        return ArchiveAction(configurationName: configurationName,
                             revealArchiveInOrganizer: revealArchiveInOrganizer,
                             customArchiveName: customArchiveName,
                             preActions: preActions,
                             postActions: postActions)
    }
}

public extension Scheme {
    static func test(name: String = "Test",
                     shared: Bool = false,
                     buildAction: BuildAction? = BuildAction.test(),
                     testAction: TestAction? = TestAction.test(),
                     runAction: RunAction? = RunAction.test(),
                     archiveAction: ArchiveAction? = ArchiveAction.test()) -> Scheme {
        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction,
                      archiveAction: archiveAction)
    }
}
