import Foundation
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
    public let buildDuration: TimeInterval?

    public init(
        name: String,
        hash: String,
        source: Source,
        cacheCategory: RemoteCacheCategory,
        buildDuration: TimeInterval? = nil
    ) {
        self.name = name
        self.hash = hash
        self.source = source
        self.cacheCategory = cacheCategory
        self.buildDuration = buildDuration
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
            buildDuration: TimeInterval? = nil
        ) -> Self {
            .init(
                name: name,
                hash: hash,
                source: source,
                cacheCategory: cacheCategory,
                buildDuration: buildDuration
            )
        }
    }
#endif
