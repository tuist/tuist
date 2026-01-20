/// Cache profile type.
public enum CacheProfileType: Codable, Equatable, Sendable {
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
        self = .custom(value)
    }
}

public enum BaseCacheProfile: String, Codable, Equatable, Sendable {
    /// Replace external dependencies only (system default)
    case onlyExternal
    /// Replace as many targets as possible (all internal targets), excluding focused targets
    case allPossible
    /// No binary replacement
    case none
}

public struct CacheProfile: Codable, Equatable, Sendable {
    /// The base cache replacement policy
    public let base: BaseCacheProfile

    /// Target names or tags to replace with cached binaries (in addition to base behavior).
    /// Use `.named("MyTarget")` or `.tagged("MyTag")`.
    ///
    /// String literals like "MyTarget" and "tag:MyTag" are supported via `ExpressibleByStringLiteral`.
    public let targetQueries: [TargetQuery]

    /// Target names or tags to exclude from binary caching.
    /// These exceptions override both the base profile behavior and any targets specified in `targetQueries`.
    /// Use `.named("MyTarget")` or `.tagged("MyTag")`.
    ///
    /// String literals like "MyTarget" and "tag:MyTag" are supported via `ExpressibleByStringLiteral`.
    public let exceptTargetQueries: [TargetQuery]

    public static func profile(
        _ base: BaseCacheProfile = .onlyExternal,
        and targetQueries: [TargetQuery] = [],
        except exceptTargetQueries: [TargetQuery] = []
    ) -> Self {
        CacheProfile(
            base: base,
            targetQueries: targetQueries,
            exceptTargetQueries: exceptTargetQueries
        )
    }
}

public struct CacheProfiles: Codable, Equatable, Sendable {
    /// Named custom profiles
    public let profileByName: [String: CacheProfile]

    /// Default cache profile to use when none is specified via CLI
    public let defaultProfile: CacheProfileType

    public static func profiles(
        _ profileByName: [String: CacheProfile] = [:],
        default defaultProfile: CacheProfileType = .onlyExternal
    ) -> Self {
        CacheProfiles(profileByName: profileByName, defaultProfile: defaultProfile)
    }
}

extension CacheProfiles: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, CacheProfile)...) {
        profileByName = Dictionary(uniqueKeysWithValues: elements)
        defaultProfile = .onlyExternal
    }
}
