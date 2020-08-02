import Foundation

public struct BuildAction: Equatable, Codable {
    public let targets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    public init(targets: [TargetReference],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = [])
    {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
    }
}
