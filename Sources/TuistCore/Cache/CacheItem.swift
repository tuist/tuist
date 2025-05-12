import Path

public struct CacheItem: Hashable, Equatable, Codable {
    /// Cache items can either come from a local or a remote cache
    public enum Source: Hashable, Equatable, Codable {
        case remote, local, miss
    }

    public let name: String
    public let hash: String
    public let source: Source
    public let cacheCategory: RemoteCacheCategory
    public let time: Double?

    public init(
        name: String,
        hash: String,
        source: Source,
        cacheCategory: RemoteCacheCategory,
        time: Double?
    ) {
        self.name = name
        self.hash = hash
        self.source = source
        self.cacheCategory = cacheCategory
        self.time = time
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine("cache-item")
        hasher.combine(hash)
    }
}

#if DEBUG
    extension CacheItem {
        public static func test(
            name: String = "Target",
            hash: String = "cache-item-hash",
            source: Source = .local,
            cacheCategory: RemoteCacheCategory = .selectiveTests,
            time: Double? = nil
        ) -> Self {
            .init(
                name: name,
                hash: hash,
                source: source,
                cacheCategory: cacheCategory,
                time: time
            )
        }
    }
#endif
