import XcodeGraph

/// Cache profile type.
public enum CacheProfileType: Codable, Equatable, Sendable, Hashable {
    /// Replace external dependencies only (system default)
    case onlyExternal
    /// Replace as many targets as possible with cached binaries
    case allPossible
    /// No binary replacement, build everything from source
    case none
    /// Use named custom profile from `profiles` dictionary
    case custom(String)
}

public enum BaseCacheProfile: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    /// Replace external dependencies only (system default)
    case onlyExternal = "only-external"
    /// Replace as many targets as possible (all internal targets), excluding focused targets
    case allPossible = "all-possible"
    /// No binary replacement
    case none = "none"
}

public struct CacheProfile: Codable, Equatable, Sendable, Hashable {
    /// The base cache replacement policy
    public let base: BaseCacheProfile

    /// Target names or tags to replace with cached binaries (in addition to base behavior)
    public let targetQueries: [TargetQuery]

    public init(
        base: BaseCacheProfile,
        targetQueries: [TargetQuery]
    ) {
        self.base = base
        self.targetQueries = targetQueries
    }
}

public struct CacheProfiles: Codable, Equatable, Sendable, Hashable {
    /// Named custom profiles
    public let profileByName: [String: CacheProfile]

    /// Default cache profile to use when none is specified via CLI
    public let defaultProfile: CacheProfileType

    public init(
        _ profileByName: [String: CacheProfile],
        default defaultProfile: CacheProfileType
    ) {
        self.profileByName = profileByName
        self.defaultProfile = defaultProfile
    }
}

public struct CacheOptions: Codable, Equatable, Sendable, Hashable {
    public var keepSourceTargets: Bool
    public var profiles: CacheProfiles

    public init(
        keepSourceTargets: Bool,
        profiles: CacheProfiles
    ) {
        self.keepSourceTargets = keepSourceTargets
        self.profiles = profiles
    }
}

#if DEBUG
    extension CacheOptions {
        public static func test(
            keepSourceTargets: Bool = false,
            profiles: CacheProfiles = .init([:], default: .onlyExternal)
        ) -> Self {
            .init(
                keepSourceTargets: keepSourceTargets,
                profiles: profiles
            )
        }
    }
#endif
