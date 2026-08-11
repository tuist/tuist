import TuistConfig
import TuistCore
import XcodeGraph

/// A decider that determines whether a target should be replaced with a cached binary.
public protocol TargetReplacementDeciding {
    /// Determines whether a target should be replaced with a cached binary.
    /// - Parameters:
    ///   - project: The project containing the target.
    ///   - target: The target to check.
    /// - Returns: `true` if the target should be replaced.
    func shouldReplace(project: Project, target: Target) -> Bool
}

/// A decider that chooses to replace targets based on a cache profile.
public struct CacheProfileTargetReplacementDecider: TargetReplacementDeciding {
    private let base: BaseCacheProfile
    private let profileTargets: TargetQueryMatcher
    private let focusedTargets: TargetQueryMatcher

    public init(profile: CacheProfile, exceptions: Set<TargetQuery>) {
        base = profile.base
        profileTargets = TargetQueryMatcher(profile.targetQueries)
        focusedTargets = TargetQueryMatcher(exceptions.union(profile.exceptTargetQueries))
    }

    public func shouldReplace(project: Project, target: Target) -> Bool {
        if focusedTargets.matches(targetName: target.name, tags: target.metadata.tags) { return false }

        switch project.type {
        case .external:
            switch base {
            case .none:
                return false
            case .onlyExternal, .allPossible:
                return true
            }
        case .local:
            switch base {
            case .allPossible:
                return true
            case .onlyExternal, .none:
                return profileTargets.matches(targetName: target.name, tags: target.metadata.tags)
            }
        }
    }
}
