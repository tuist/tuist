import Foundation
import TSCBasic

public struct TestAction: Equatable, Codable {
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
    public var diagnosticsOptions: Set<SchemeDiagnosticsOption>
    public var language: String?
    public var region: String?

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
        diagnosticsOptions: Set<SchemeDiagnosticsOption>,
        language: String? = nil,
        region: String? = nil,
        testPlans: [TestPlan]? = nil
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
    }
}
