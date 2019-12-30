import Basic
import Foundation

public struct BuildAction: Equatable {
    // MARK: - Attributes

    public let targets: [TargetReference]
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]

    // MARK: - Init

    public init(targets: [TargetReference] = [],
                preActions: [ExecutionAction] = [],
                postActions: [ExecutionAction] = []) {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
    }

    // MARK: - Equatable

    public static func == (lhs: BuildAction, rhs: BuildAction) -> Bool {
        lhs.targets == rhs.targets &&
            lhs.preActions == rhs.preActions &&
            lhs.postActions == rhs.postActions
    }
}
