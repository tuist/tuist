import Foundation
import Path

public struct BuildAction: Equatable, Codable, Sendable {
    // MARK: - Attributes

    public var targets: [TargetReference]
    /// Queries matching the targets to build. They are resolved against the whole graph, and the matched targets are
    /// appended to `targets` before the scheme is generated.
    public var targetQueries: [TargetQuery]
    public var preActions: [ExecutionAction]
    public var postActions: [ExecutionAction]
    public var parallelizeBuild: Bool
    public var runPostActionsOnFailure: Bool
    public var findImplicitDependencies: Bool

    // MARK: - Init

    public init(
        targets: [TargetReference] = [],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        parallelizeBuild: Bool = true,
        runPostActionsOnFailure: Bool = false,
        findImplicitDependencies: Bool = true,
        targetQueries: [TargetQuery] = []
    ) {
        self.targets = targets
        self.targetQueries = targetQueries
        self.preActions = preActions
        self.postActions = postActions
        self.parallelizeBuild = parallelizeBuild
        self.runPostActionsOnFailure = runPostActionsOnFailure
        self.findImplicitDependencies = findImplicitDependencies
    }

    #if DEBUG
        public static func test(
            // swiftlint:disable:next force_try
            targets: [TargetReference] = [TargetReference(projectPath: try! AbsolutePath(validating: "/Project"), name: "App")],
            preActions: [ExecutionAction] = [],
            postActions: [ExecutionAction] = [],
            targetQueries: [TargetQuery] = []
        ) -> BuildAction {
            BuildAction(
                targets: targets,
                preActions: preActions,
                postActions: postActions,
                targetQueries: targetQueries
            )
        }
    #endif
}
