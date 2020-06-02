import Foundation
import TSCBasic

public struct TestAction: Equatable {
    // MARK: - Attributes

    public let targets: [TestableTarget]
    public let arguments: Arguments?
    public let configurationName: String
    public let coverage: Bool
    public let codeCoverageTargets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]
    public let diagnosticsOptions: Set<SchemeDiagnosticsOption>

    // MARK: - Init

    public init(targets: [TestableTarget],
                arguments: Arguments?,
                configurationName: String,
                coverage: Bool,
                codeCoverageTargets: [TargetReference],
                preActions: [ExecutionAction],
                postActions: [ExecutionAction],
                diagnosticsOptions: Set<SchemeDiagnosticsOption>) {
        self.targets = targets
        self.arguments = arguments
        self.configurationName = configurationName
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
        self.diagnosticsOptions = diagnosticsOptions
    }
}
