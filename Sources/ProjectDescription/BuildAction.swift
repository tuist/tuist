import Foundation

public struct BuildAction: Equatable, Codable {
    public let targets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]
    public let runPostActionsOnFailure: Bool

    public init(targets: [TargetReference],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = [],
                runPostActionsOnFailure: Bool = false)
    {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
        self.runPostActionsOnFailure = runPostActionsOnFailure
    }
}
