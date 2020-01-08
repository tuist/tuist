import Foundation

public struct TestAction: Equatable, Codable {
    public let targets: [TestableTarget]
    public let arguments: Arguments?
    public let configurationName: String
    public let coverage: Bool
    public let codeCoverageTargets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    public init(targets: [TestableTarget] = [],
                arguments: Arguments? = nil,
                configurationName: String,
                coverage: Bool = false,
                codeCoverageTargets: [TargetReference] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.arguments = arguments
        self.configurationName = configurationName
        self.coverage = coverage
        self.preActions = preActions
        self.postActions = postActions
        self.codeCoverageTargets = codeCoverageTargets
    }

    public init(targets: [TestableTarget],
                arguments: Arguments? = nil,
                config: PresetBuildConfiguration = .debug,
                coverage: Bool = false,
                codeCoverageTargets: [TargetReference] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.init(targets: targets,
                  arguments: arguments,
                  configurationName: config.name,
                  coverage: coverage,
                  codeCoverageTargets: codeCoverageTargets,
                  preActions: preActions,
                  postActions: postActions)
    }
}
