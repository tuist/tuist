import Foundation

/// An action that builds products.
public struct BuildAction: Equatable, Codable {
    /// A list of targets to build, which are defined in the project.
    public var targets: [TargetReference]
    /// A list of actions that are executed before starting the build process.
    public var preActions: [ExecutionAction]
    /// A list of actions that are executed after the build process.
    public var postActions: [ExecutionAction]
    /// Whether the post actions should be run in the case of a failure
    public var runPostActionsOnFailure: Bool

    public init(
        targets: [TargetReference],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        runPostActionsOnFailure: Bool = false
    ) {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
        self.runPostActionsOnFailure = runPostActionsOnFailure
    }
}
