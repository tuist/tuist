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

extension CacheProfileType: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        switch BaseCacheProfile(rawValue: value) {
        case .onlyExternal:
            self = .onlyExternal
        case .allPossible:
            self = .allPossible
        case .none?:
            self = .none
        case nil:
            self = .custom(value)
        }
    }
}

public enum BaseCacheProfile: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    /// Replace external dependencies only (system default)
    case onlyExternal = "only-external"
    /// Replace as many targets as possible (all internal targets), excluding focused targets
    case allPossible = "all-possible"
    /// No binary replacement
    case none
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

    /// A cache profile that replaces external dependencies only
    public static let onlyExternal = CacheProfile(base: .onlyExternal, targetQueries: [])

    /// A cache profile that replaces as many targets as possible with cached binaries
    public static let allPossible = CacheProfile(base: .allPossible, targetQueries: [])

    /// A cache profile that disables all binary caching
    public static let none = CacheProfile(base: .none, targetQueries: [])
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
