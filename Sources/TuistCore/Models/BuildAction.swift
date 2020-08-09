import Foundation
import TSCBasic

public struct BuildAction: Equatable {
    // MARK: - Attributes

    public var targets: [TargetReference]
    public var preActions: [ExecutionAction]
    public var postActions: [ExecutionAction]

    // MARK: - Init

    public init(targets: [TargetReference] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = [])
    {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
    }
}
