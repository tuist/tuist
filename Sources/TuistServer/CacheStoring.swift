#if canImport(TuistCore)
    import Foundation
    import Mockable
    import Path
    import TuistCache
    import TuistCore
    import XcodeGraph

    public struct CacheStorableTarget: Hashable, Equatable {
        public let target: GraphTarget
        public let hash: String
        public let time: Double?
        public var name: String { target.target.name }

        public init(target: GraphTarget, hash: String, time: Double? = nil) {
            self.target = target
            self.hash = hash
            self.time = time
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine("cache-storable")
            hasher.combine(hash)
        }
    }

    public struct CacheStorableItem: Hashable, Equatable {
        public let name: String
        public let hash: String
        public let metadata: CacheStorableItemMetadata

        public init(name: String, hash: String, metadata: CacheStorableItemMetadata = CacheStorableItemMetadata()) {
            self.name = name
            self.hash = hash
            self.metadata = metadata
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine("cache-storable")
            hasher.combine(hash)
        }
    }

    public struct CacheStorableItemMetadata: Hashable, Equatable, Codable {
        public let time: Double?
        public init(time: Double? = nil) {
            self.time = time
        }
    }

    @Mockable
    public protocol CacheStoring {
        func fetch(
            _ items: Set<CacheStorableItem>,
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheItem: AbsolutePath]
        func store(
            _ items: [CacheStorableItem: [AbsolutePath]],
            cacheCategory: RemoteCacheCategory
        ) async throws
    }

    extension CacheStoring {
        public func fetch(
            _ targets: Set<CacheStorableTarget>,
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheStorableTarget: AbsolutePath] {
            Dictionary(
                uniqueKeysWithValues: try await fetch(
                    Set(targets.map { CacheStorableItem(name: $0.name, hash: $0.hash) }),
                    cacheCategory: cacheCategory
                )
                .compactMap { item, path -> (CacheStorableTarget, AbsolutePath)? in
                    guard let target = targets.first(where: { $0.hash == item.hash }) else {
                        return nil
                    }
                    return (target, path)
                }
            )
        }

        public func store(
            _ targets: [CacheStorableTarget: [AbsolutePath]],
            cacheCategory: RemoteCacheCategory
        ) async throws {
            let items = Dictionary(
                uniqueKeysWithValues: targets.map {
                    target, paths -> (CacheStorableItem, [AbsolutePath]) in
                    (
                        CacheStorableItem(
                            name: target.name,
                            hash: target.hash,
                            metadata: CacheStorableItemMetadata(time: target.time)
                        ),
                        paths
                    )
                }
            )
            try await store(items, cacheCategory: cacheCategory)
        }
    }
#endif
