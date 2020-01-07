import Basic
import Foundation

public struct TestAction: Equatable {
    // MARK: - Attributes

    public let targets: [TestableTarget]
    public let arguments: Arguments?
    public let configurationName: String
    public let coverage: Bool
    public let codeCoverageTargets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

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

    // MARK: - Equatable

    public static func == (lhs: TestAction, rhs: TestAction) -> Bool {
        lhs.targets == rhs.targets &&
            lhs.arguments == rhs.arguments &&
            lhs.configurationName == rhs.configurationName &&
            lhs.coverage == rhs.coverage &&
            lhs.codeCoverageTargets == rhs.codeCoverageTargets &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}
