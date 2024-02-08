import Foundation
import TSCBasic
import TuistSupport
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
        diagnosticsOptions: SchemeDiagnosticsOptions = SchemeDiagnosticsOptions(mainThreadCheckerEnabled: true),
        language: String? = nil,
        region: String? = nil,
        preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
        testPlans: [TestPlan]? = nil,
        skippedTests: [String]? = nil
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
            preferredScreenCaptureFormat: preferredScreenCaptureFormat,
            testPlans: testPlans,
            skippedTests: skippedTests
        )
    }
}
