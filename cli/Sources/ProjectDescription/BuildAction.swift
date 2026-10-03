/// An action that builds products.
///
/// It's initialized with the `.buildAction` static method.
public struct BuildAction: Equatable, Codable, Sendable {
    /// A list of targets to build, which are defined in the project.
    public var targets: [TargetReference]
    /// A list of queries matching the targets to build. They are resolved against every target of the generated
    /// graph, so they can match targets that live in other projects, and the matched targets are built in addition
    /// to the ones listed in ``BuildAction/targets``.
    public var targetQueries: [TargetQuery]
    /// A list of actions that are executed before starting the build process.
    public var preActions: [ExecutionAction]
    /// A list of actions that are executed after the build process.
    public var postActions: [ExecutionAction]
    /// Defines the order in which targets are built.
    public var buildOrder: BuildOrder
    /// Whether the post actions should be run in the case of a failure
    public var runPostActionsOnFailure: Bool
    /// Whether Xcode should be allowed to find dependencies implicitly. The default is `true`.
    public var findImplicitDependencies: Bool

    /// Returns a build action.
    /// - Parameters:
    ///   - targets: A list of targets to build, which are defined in the project.
    ///   - matching: A list of queries matching the targets to build. Queries are resolved against every target of
    /// the generated graph, so they can match targets that live in other projects:
    /// `.buildAction(matching: ["*Kit", "tag:frameworks"])`.
    ///   - preActions: A list of actions that are executed before starting the build process.
    ///   - postActions: A list of actions that are executed after the build process.
    ///   - buildOrder: Defines the order in which targets are built. Defaults to `.dependency`.
    ///   - runPostActionsOnFailure: Whether the post actions should be run in the case of a failure
    ///   - findImplicitDependencies: Whether Xcode should be allowed to find dependencies implicitly. The default is `true`.
    /// - Returns: Initialized build action.
    public static func buildAction(
        targets: [TargetReference] = [],
        matching targetQueries: [TargetQuery] = [],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        buildOrder: BuildOrder = .dependency,
        runPostActionsOnFailure: Bool = false,
        findImplicitDependencies: Bool = true
    ) -> BuildAction {
        BuildAction(
            targets: targets,
            targetQueries: targetQueries,
            preActions: preActions,
            postActions: postActions,
            buildOrder: buildOrder,
            runPostActionsOnFailure: runPostActionsOnFailure,
            findImplicitDependencies: findImplicitDependencies
        )
    }
}
