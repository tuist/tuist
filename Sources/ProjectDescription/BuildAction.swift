import Foundation

/// An action that builds products.
///
/// It's initialized with the `.buildAction` static method.
public struct BuildAction: Equatable, Codable {
    /// A list of targets to build, which are defined in the project.
    public var targets: [TargetReference]
    /// A list of actions that are executed before starting the build process.
    public var preActions: [ExecutionAction]
    /// A list of actions that are executed after the build process.
    public var postActions: [ExecutionAction]
    /// Whether the post actions should be run in the case of a failure
    public var runPostActionsOnFailure: Bool

    /// Returns a build action.
    /// - Parameters:
    ///   - targets: A list of targets to build, which are defined in the project.
    ///   - preActions: A list of actions that are executed before starting the build process.
    ///   - postActions: A list of actions that are executed after the build process.
    ///   - runPostActionsOnFailure: Whether the post actions should be run in the case of a failure
    /// - Returns: Initialized build action.
    public static func buildAction(
        targets: [TargetReference],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        runPostActionsOnFailure: Bool = false
    ) -> BuildAction {
        BuildAction(
            targets: targets,
            preActions: preActions,
            postActions: postActions,
            runPostActionsOnFailure: runPostActionsOnFailure
        )
    }
}
