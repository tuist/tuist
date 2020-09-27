import Foundation
import TSCBasic
@testable import TuistCore

public extension TestAction {
    static func test(targets: [TestableTarget] = [TestableTarget(target: TargetReference(projectPath: "/Project", name: "AppTests"))],
                     arguments: Arguments? = Arguments.test(),
                     configurationName: String = BuildConfiguration.debug.name,
                     coverage: Bool = false,
                     codeCoverageTargets: [TargetReference] = [],
                     preActions: [ExecutionAction] = [],
                     postActions: [ExecutionAction] = [],
                     diagnosticsOptions: Set<SchemeDiagnosticsOption> = Set(),
                     language: String? = nil,
                     region: String? = nil) -> TestAction
    {
        TestAction(targets: targets,
                   arguments: arguments,
                   configurationName: configurationName,
                   coverage: coverage,
                   codeCoverageTargets: codeCoverageTargets,
                   preActions: preActions,
                   postActions: postActions,
                   diagnosticsOptions: diagnosticsOptions,
                   language: language,
                   region: region)
    }
}
