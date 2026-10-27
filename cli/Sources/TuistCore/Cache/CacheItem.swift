public struct CacheItem: Hashable, Equatable, Codable {
    /// Cache items can either come from a local or a remote cache
    public enum Source: Hashable, Equatable, Codable {
        case remote, local, miss
    }

    public let name: String
    public let hash: String
    public let source: Source
    public let cacheCategory: RemoteCacheCategory
    /// Whether a binary taken from the cache carries coverage counters, so a run collecting
    /// coverage measures its code; nil for a miss, and until the binary has been looked at.
    public let instrumented: Bool?

    public init(
        name: String,
        hash: String,
        source: Source,
        cacheCategory: RemoteCacheCategory,
        instrumented: Bool? = nil
    ) {
        self.name = name
        self.hash = hash
        self.source = source
        self.cacheCategory = cacheCategory
        self.instrumented = instrumented
    }

    public func with(instrumented: Bool?) -> CacheItem {
        CacheItem(name: name, hash: hash, source: source, cacheCategory: cacheCategory, instrumented: instrumented)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine("cache-item")
        hasher.combine(hash)
    }

    #if DEBUG
        public static func test(
            name: String = "Target",
            hash: String = "cache-item-hash",
            source: Source = .local,
            cacheCategory: RemoteCacheCategory = .selectiveTests,
            instrumented: Bool? = nil
        ) -> Self {
            .init(
                name: name,
                hash: hash,
                source: source,
                cacheCategory: cacheCategory,
                instrumented: instrumented
            )
        }
    #endif
}
