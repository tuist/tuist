extension Tuist {
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
        public let targets: [TargetQuery]

        public static func profile(
            base: BaseCacheProfile = .onlyExternal,
            targets: [TargetQuery] = []
        ) -> Self {
            CacheProfile(
                base: base,
                targets: targets
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
}
