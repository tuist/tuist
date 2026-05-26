extension Tuist {
    /// Represents a cache storage backend.
    public enum CacheStorageOption: Codable, Equatable, Sendable {
        /// Store and fetch cached binaries on the local machine.
        case local
        /// Store and fetch cached binaries from the remote Tuist server.
        case remote
    }

    /// Options for caching.
    public struct CacheOptions: Codable, Equatable, Sendable {
        public var keepSourceTargets: Bool
        public var profiles: CacheProfiles
        /// The storage backends to use for caching. Defaults to `[.local, .remote]`.
        public var storages: [CacheStorageOption]

        public static func options(
            keepSourceTargets: Bool = false,
            profiles: CacheProfiles = [:],
            storages: [CacheStorageOption] = [.local, .remote]
        ) -> Self {
            self.init(
                keepSourceTargets: keepSourceTargets,
                profiles: profiles,
                storages: storages
            )
        }
    }
}
