import Foundation
import TSCBasic

public struct TestAction: Equatable {
    // MARK: - Attributes

    public var targets: [TestableTarget]
    public var arguments: Arguments?
    public var configurationName: String
    public var coverage: Bool
    public var codeCoverageTargets: [TargetReference]
    public var preActions: [ExecutionAction]
    public var postActions: [ExecutionAction]
    public var diagnosticsOptions: Set<SchemeDiagnosticsOption>
    public var language: String?
    public var region: String?

    // MARK: - Init

    public init(targets: [TestableTarget],
                arguments: Arguments?,
                configurationName: String,
                coverage: Bool,
                codeCoverageTargets: [TargetReference],
                preActions: [ExecutionAction],
                postActions: [ExecutionAction],
                diagnosticsOptions: Set<SchemeDiagnosticsOption>,
                language: String? = nil,
                region: String? = nil)
    {
        self.targets = targets
        self.arguments = arguments
        self.configurationName = configurationName
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
        self.diagnosticsOptions = diagnosticsOptions
        self.language = language
        self.region = region
    }
}
