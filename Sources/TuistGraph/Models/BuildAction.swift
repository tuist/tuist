import Foundation
import TSCBasic

public struct BuildAction: Equatable, Codable {
    // MARK: - Attributes

    public var targets: [Target]
    public var preActions: [ExecutionAction]
    public var postActions: [ExecutionAction]
    public var runPostActionsOnFailure: Bool

    // MARK: - Init

    public init(
        targets: [Target] = [],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        runPostActionsOnFailure: Bool = false
    ) {
        self.targets = targets
        self.preActions = preActions
        self.postActions = postActions
        self.runPostActionsOnFailure = runPostActionsOnFailure
    }

    public init(
        targetReferences: [TargetReference],
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        runPostActionsOnFailure: Bool = false
    ) {
        targets = targetReferences.map { .init(targetReference: $0) }
        self.preActions = preActions
        self.postActions = postActions
        self.runPostActionsOnFailure = runPostActionsOnFailure
    }
}

extension BuildAction {
    public struct Target: Hashable, Codable {
        public enum BuildFor: Codable, CaseIterable {
            case running, testing, profiling, archiving, analyzing
        }

        public var targetReference: TargetReference
        public var buildFor: [BuildFor]

        public init(targetReference: TargetReference, buildFor: [BuildFor] = BuildFor.allCases) {
            self.targetReference = targetReference
            self.buildFor = buildFor
        }
    }
}
