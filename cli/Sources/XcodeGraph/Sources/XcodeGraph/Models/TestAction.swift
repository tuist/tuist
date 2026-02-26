import Foundation
import Path

public struct TestAction: Equatable, Codable, Sendable {
    // MARK: - Attributes

    public var testPlans: [TestPlan]?
    public var targets: [TestableTarget]
    public var arguments: Arguments?
    public var configurationName: String
    public var attachDebugger: Bool
    public var coverage: Bool
    public var codeCoverageTargets: [TargetReference]
    public var expandVariableFromTarget: TargetReference?
    public var preActions: [ExecutionAction]
    public var postActions: [ExecutionAction]
    public var diagnosticsOptions: SchemeDiagnosticsOptions
    public var language: String?
    public var region: String?
    public var preferredScreenCaptureFormat: ScreenCaptureFormat?
    public var skippedTests: [String]?

    // MARK: - Init

    public init(
        targets: [TestableTarget],
        arguments: Arguments?,
        configurationName: String,
        attachDebugger: Bool,
        coverage: Bool,
        codeCoverageTargets: [TargetReference],
        expandVariableFromTarget: TargetReference?,
        preActions: [ExecutionAction],
        postActions: [ExecutionAction],
        diagnosticsOptions: SchemeDiagnosticsOptions,
        language: String? = nil,
        region: String? = nil,
        preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
        testPlans: [TestPlan]? = nil,
        skippedTests: [String]? = nil
    ) {
        self.testPlans = testPlans
        self.targets = targets
        self.arguments = arguments
        self.configurationName = configurationName
        self.attachDebugger = attachDebugger
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
        self.expandVariableFromTarget = expandVariableFromTarget
        self.diagnosticsOptions = diagnosticsOptions
        self.language = language
        self.region = region
        self.preferredScreenCaptureFormat = preferredScreenCaptureFormat
        self.skippedTests = skippedTests
    }
}

#if DEBUG
    extension TestAction {
        public static func test(
            targets: [TestableTarget] = [TestableTarget(target: TargetReference(
                // swiftlint:disable:next force_try
                projectPath: try! AbsolutePath(validating: "/Project"),
                name: "AppTests"
            ))],
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
#endif
