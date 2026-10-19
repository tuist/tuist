/// An action that builds products.
///
/// It's initialized with the `.buildAction` static method.
public struct BuildAction: Equatable, Codable, Sendable {
    /// A list of targets to build, which are defined in the project.
    public var targets: [TargetReference]
    /// The build purposes enabled for each target. Targets absent from this dictionary are built for all purposes;
    /// an empty set disables the target for every purpose.
    public var buildFor: [TargetReference: Set<BuildActionTarget.BuildFor>]
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
    ///   - preActions: A list of actions that are executed before starting the build process.
    ///   - postActions: A list of actions that are executed after the build process.
    ///   - buildOrder: Defines the order in which targets are built. Defaults to `.dependency`.
    ///   - runPostActionsOnFailure: Whether the post actions should be run in the case of a failure
    ///   - findImplicitDependencies: Whether Xcode should be allowed to find dependencies implicitly. The default is `true`.
    /// - Returns: Initialized build action.
    public static func buildAction(
        targets: [TargetReference],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        buildOrder: BuildOrder = .dependency,
        runPostActionsOnFailure: Bool = false,
        findImplicitDependencies: Bool = true
    ) -> BuildAction {
        BuildAction(
            targets: targets,
            buildFor: [:],
            preActions: preActions,
            postActions: postActions,
            buildOrder: buildOrder,
            runPostActionsOnFailure: runPostActionsOnFailure,
            findImplicitDependencies: findImplicitDependencies
        )
    }

    /// Returns a build action with independently configurable build purposes for each target.
    /// Repeated target references are included once, with their build purposes combined.
    /// - Parameters:
    ///   - buildActionTargets: Targets and the build purposes enabled for each one. An empty
    ///     build purpose set disables that target for every purpose.
    ///   - preActions: A list of actions that are executed before starting the build process.
    ///   - postActions: A list of actions that are executed after the build process.
    ///   - buildOrder: Defines the order in which targets are built. Defaults to `.dependency`.
    ///   - runPostActionsOnFailure: Whether the post actions should be run in the case of a failure.
    ///   - findImplicitDependencies: Whether Xcode should be allowed to find dependencies implicitly. The default is `true`.
    /// - Returns: An initialized build action.
    public static func buildAction(
        buildActionTargets: [BuildActionTarget],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        buildOrder: BuildOrder = .dependency,
        runPostActionsOnFailure: Bool = false,
        findImplicitDependencies: Bool = true
    ) -> BuildAction {
        var targets: [TargetReference] = []
        var seenTargets: Set<TargetReference> = []
        for buildActionTarget in buildActionTargets {
            guard seenTargets.insert(buildActionTarget.target).inserted else { continue }
            targets.append(buildActionTarget.target)
        }

        return BuildAction(
            targets: targets,
            buildFor: Dictionary(
                buildActionTargets.map { ($0.target, $0.buildFor) },
                uniquingKeysWith: { existing, duplicate in existing.union(duplicate) }
            ),
            preActions: preActions,
            postActions: postActions,
            buildOrder: buildOrder,
            runPostActionsOnFailure: runPostActionsOnFailure,
            findImplicitDependencies: findImplicitDependencies
        )
    }
}

/// A target in a scheme's build action and the purposes for which Xcode should build it.
public struct BuildActionTarget: Equatable, Codable, Sendable {
    /// A purpose for which Xcode can build a target in a scheme.
    public enum BuildFor: String, Codable, CaseIterable, Sendable {
        /// Build the target when analyzing the scheme.
        case analyzing
        /// Build the target when archiving the scheme.
        case archiving
        /// Build the target when profiling the scheme.
        case profiling
        /// Build the target when running the scheme.
        case running
        /// Build the target when testing the scheme.
        case testing
    }

    /// The target included in the build action.
    public var target: TargetReference
    /// The purposes for which Xcode builds the target. An empty set disables the target for every purpose.
    public var buildFor: Set<BuildFor>

    /// Creates a build action target that references a target in the current project.
    /// - Parameters:
    ///   - name: The name of the target.
    ///   - buildFor: The purposes for which Xcode builds the target. Defaults to all purposes;
    ///     an empty set disables it for every purpose.
    /// - Returns: A build action target referencing the named target.
    public static func target(
        _ name: String,
        buildFor: Set<BuildFor> = Set(BuildFor.allCases)
    ) -> BuildActionTarget {
        .init(target: .target(name), buildFor: buildFor)
    }

    /// Creates a build action target that references a target in another project.
    /// - Parameters:
    ///   - path: The path to the project containing the target.
    ///   - target: The name of the target.
    ///   - buildFor: The purposes for which Xcode builds the target. Defaults to all purposes;
    ///     an empty set disables it for every purpose.
    /// - Returns: A build action target referencing the target in the specified project.
    public static func project(
        path: Path,
        target: String,
        buildFor: Set<BuildFor> = Set(BuildFor.allCases)
    ) -> BuildActionTarget {
        .init(target: .project(path: path, target: target), buildFor: buildFor)
    }
}
