import Foundation
import TuistCore
import XcodeGraph

/// A decider that determines whether a target should be replaced with a cached binary.
protocol TargetReplacementDeciding {
    /// Determines whether a target should be replaced with a cached binary.
    /// - Parameters:
    ///   - project: The project containing the target.
    ///   - target: The target to check.
    /// - Returns: `true` if the target should be replaced.
    func shouldReplace(project: Project, target: Target) -> Bool
}

/// A decider that chooses to replace only external targets.
struct ExternalOnlyTargetReplacementDecider: TargetReplacementDeciding {
    func shouldReplace(project: Project, target _: Target) -> Bool {
        project.isExternal
    }
}

/// A decider that chooses to replace all targets, except for those that are explicitly excluded.
struct AllPossibleTargetReplacementDecider: TargetReplacementDeciding {
    private let exceptionNames: Set<String>
    private let exceptionTags: Set<String>

    init(exceptions: Set<TargetQuery>) {
        var names = Set<String>()
        var tags = Set<String>()
        for exception in exceptions {
            switch exception {
            case let .named(name):
                names.insert(name)
            case let .tagged(tag):
                tags.insert(tag)
            }
        }
        exceptionNames = names
        exceptionTags = tags
    }

    func shouldReplace(project _: Project, target: Target) -> Bool {
        if exceptionNames.contains(target.name) {
            return false
        }
        if !exceptionTags.isEmpty, !target.metadata.tags.isDisjoint(with: exceptionTags) {
            return false
        }
        return true
    }
}

extension Project {
    fileprivate var isExternal: Bool {
        switch type {
        case .external:
            return true
        case .local:
            return false
        }
    }
}
