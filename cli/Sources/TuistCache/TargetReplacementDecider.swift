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
    private let profileTargetProducts: Set<Product>
    private let focusedTargetNames: Set<String>
    private let focusedTargetTags: Set<String>
    private let focusedTargetProducts: Set<Product>

    public init(profile: CacheProfile, exceptions: Set<TargetQuery>) {
        base = profile.base

        var names = Set<String>()
        var tags = Set<String>()
        var products = Set<Product>()
        for query in profile.targetQueries {
            switch query {
            case let .named(name):
                names.insert(name)
            case let .tagged(tag):
                tags.insert(tag)
            case let .product(product):
                products.insert(product)
            }
        }
        profileTargetNames = names
        profileTargetTags = tags
        profileTargetProducts = products

        names.removeAll()
        tags.removeAll()
        products.removeAll()
        for exception in exceptions.union(profile.exceptTargetQueries) {
            switch exception {
            case let .named(name):
                names.insert(name)
            case let .tagged(tag):
                tags.insert(tag)
            case let .product(product):
                products.insert(product)
            }
        }
        focusedTargetNames = names
        focusedTargetTags = tags
        focusedTargetProducts = products
    }

    public func shouldReplace(project: Project, target: Target) -> Bool {
        if focusedTargetNames.contains(target.name) { return false }
        if !target.metadata.tags.isDisjoint(with: focusedTargetTags) { return false }
        if focusedTargetProducts.contains(target.product) { return false }

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
                if profileTargetProducts.contains(target.product) { return true }
                return false
            }
        }
    }
}
