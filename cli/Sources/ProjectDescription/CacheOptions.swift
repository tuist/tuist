extension Tuist {
    /// Options for caching.
    public struct CacheOptions: Codable, Equatable, Sendable {
        public var keepSourceTargets: Bool
        public var profiles: CacheProfiles

        public static func options(
            keepSourceTargets: Bool = false,
            profiles: CacheProfiles = [:]
        ) -> Self {
            self.init(
                keepSourceTargets: keepSourceTargets,
                profiles: profiles
            )
        }
    }
}
