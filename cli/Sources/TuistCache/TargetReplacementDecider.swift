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
    private let profileTargetNames: Set<String>
    private let profileTargetTags: Set<String>
    private let focusedTargetNames: Set<String>
    private let focusedTargetTags: Set<String>

    public init(profile: CacheProfile, exceptions: Set<TargetQuery>) {
        base = profile.base

        var names = Set<String>()
        var tags = Set<String>()
        for query in profile.targetQueries {
            switch query {
            case let .named(name):
                names.insert(name)
            case let .tagged(tag):
                tags.insert(tag)
            }
        }
        profileTargetNames = names
        profileTargetTags = tags

        names.removeAll()
        tags.removeAll()
        for exception in exceptions {
            switch exception {
            case let .named(name):
                names.insert(name)
            case let .tagged(tag):
                tags.insert(tag)
            }
        }
        focusedTargetNames = names
        focusedTargetTags = tags
    }

    public func shouldReplace(project: Project, target: Target) -> Bool {
        if focusedTargetNames.contains(target.name) { return false }
        if !target.metadata.tags.isDisjoint(with: focusedTargetTags) { return false }

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
                if profileTargetNames.contains(target.name) { return true }
                if !target.metadata.tags.isDisjoint(with: profileTargetTags) { return true }
                return false
            }
        }
    }
}
