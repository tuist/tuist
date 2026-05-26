extension Tuist {
    /// Represents the backend used for the remote module cache.
    public enum RemoteCacheBackend: Codable, Equatable, Sendable {
        /// Store and fetch module cache artifacts through regional cache endpoints.
        case regional
        /// Store and fetch module cache artifacts through the legacy Tuist server endpoints.
        case legacy
    }

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
        /// The backend to use for remote module cache operations. Defaults to `.regional`.
        public var remoteCacheBackend: RemoteCacheBackend

        public static func options(
            keepSourceTargets: Bool = false,
            profiles: CacheProfiles = [:],
            storages: [CacheStorageOption] = [.local, .remote],
            remoteCacheBackend: RemoteCacheBackend = .regional
        ) -> Self {
            self.init(
                keepSourceTargets: keepSourceTargets,
                profiles: profiles,
                storages: storages,
                remoteCacheBackend: remoteCacheBackend
            )
        }
    }
}
