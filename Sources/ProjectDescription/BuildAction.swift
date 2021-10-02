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

    /// Returns a build action.
    /// - Parameters:
    ///   - targets: Targets to be built.
    ///   - preActions: Actions to run before building.
    ///   - postActions: Actions to run after building.
    ///   - runPostActionsOnFailure: Whether pre and post actions should run on failure.
    /// - Returns: Initialized build action.
    public static func buildAction(targets: [TargetReference],
                                   preActions: [ExecutionAction] = [],
                                   postActions: [ExecutionAction] = [],
                                   runPostActionsOnFailure: Bool = false) -> BuildAction
    {
        return BuildAction(
            targets: targets,
            preActions: preActions,
            postActions: postActions,
            runPostActionsOnFailure: runPostActionsOnFailure
        )
    }
}
