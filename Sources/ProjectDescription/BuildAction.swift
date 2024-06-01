import Foundation

/// An action that builds products.
///
/// It's initialized with the `.buildAction` static method.
public struct BuildAction: Equatable, Codable, Sendable {
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
    public static func buildAction(
        targets: [Target],
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

extension BuildAction {
    public struct Target: Hashable, Codable, ExpressibleByStringInterpolation {
        public enum BuildFor: Codable, CaseIterable {
            case running, testing, profiling, archiving, analyzing
        }

        public let targetReference: TargetReference
        public let buildFor: [BuildFor]

        init(targetReference: TargetReference, buildFor: [BuildFor]) {
            self.targetReference = targetReference
            self.buildFor = buildFor
        }

        public init(stringLiteral value: String) {
            self = .init(
                targetReference: .init(stringLiteral: value),
                buildFor: BuildFor.allCases
            )
        }

        public static func project(
            path: Path,
            target: String,
            buildFor: [BuildFor] = BuildFor.allCases
        ) -> Target {
            .init(targetReference: .project(path: path, target: target), buildFor: buildFor)
        }

        public static func target(_ name: String, buildFor: [BuildFor] = BuildFor.allCases) -> Target {
            .init(targetReference: .target(name), buildFor: buildFor)
        }
    }
}
