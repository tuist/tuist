import Foundation

/// An action that builds products.
///
/// It's initialized with the `.buildAction` static method.
public struct BuildAction: Equatable, Codable, Sendable {
    
    /// It represents the reference to a target from a build action, along with the actions when the target
    /// should be built.
    public struct Target: Equatable, Codable, Sendable, ExpressibleByStringInterpolation {
        /// Xcode project actions when a build scheme action can build a target.
        public enum BuildFor: Codable, CaseIterable, Sendable {
            case running, testing, profiling, archiving, analyzing
        }

        /// The target reference.
        public var reference: TargetReference

        /// A list of Xcode actions when a target should build.
        public var buildFor: [BuildFor]?

        init(_ reference: TargetReference, buildFor: [BuildFor]?) {
            self.reference = reference
            self.buildFor = buildFor
        }
        
        public init(stringLiteral value: String) {
            self = .init(TargetReference(stringLiteral: value), buildFor: nil)
        }
        
        /// Initializes a new `BuildAction.Target`.
        /// - Parameters:
        ///   - reference: The target it references.
        ///   - buildFor: The list of actions the target reference is associated to. They represent the action when a given target is built.
        /// - Returns: An initialized `BuildAction.Target`.
        public static func target(_ reference: TargetReference, buildFor: [BuildFor]? = nil) -> Target {
            return Target(reference, buildFor: buildFor)
        }
    }
    
    /// A list of targets to build, which are defined in the project.
    public var targets: [Target]
    
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
    @available(*, deprecated, message: "Use the initializer that accepts targets as [BuildAction.Target], which supports passing the actions when targets build for each target in the list.")
    public static func buildAction(
        targets: [TargetReference],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        runPostActionsOnFailure: Bool = false
    ) -> BuildAction {
        BuildAction(
            targets: targets.map({ Target($0, buildFor: nil) }),
            preActions: preActions,
            postActions: postActions,
            runPostActionsOnFailure: runPostActionsOnFailure
        )
    }
    
    /// Returns a build action.
    /// - Parameters:
    ///   - targets: A list of targets to build, which are defined in the project.
    ///   - preActions: A list of actions that are executed before starting the build process.
    ///   - postActions: A list of actions that are executed after the build process.
    ///   - runPostActionsOnFailure: Whether the post actions should be run in the case of a failure
    /// - Returns: Initialized build action.
    public static func buildAction(
        targets: [BuildAction.Target],
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
