import Foundation
import TSCBasic
@testable import TuistGraph

extension TestAction {
    public static func test(
        targets: [TestableTarget] = [TestableTarget(target: TargetReference(projectPath: "/Project", name: "AppTests"))],
        arguments: Arguments? = Arguments.test(),
        configurationName: String = BuildConfiguration.debug.name,
        attachDebugger: Bool = true,
        coverage: Bool = false,
        codeCoverageTargets: [TargetReference] = [],
        expandVariableFromTarget: TargetReference? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        diagnosticsOptions: Set<SchemeDiagnosticsOption> = [.mainThreadChecker],
        language: String? = nil,
        region: String? = nil,
        testPlans: [TestPlan]? = nil
    ) -> TestAction {
        TestAction(
            targets: targets,
            arguments: arguments,
            configurationName: configurationName,
            attachDebugger: attachDebugger,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets,
            expandVariableFromTarget: expandVariableFromTarget,
            preActions: preActions,
            postActions: postActions,
            diagnosticsOptions: diagnosticsOptions,
            language: language,
            region: region,
            testPlans: testPlans
        )
    }
}
