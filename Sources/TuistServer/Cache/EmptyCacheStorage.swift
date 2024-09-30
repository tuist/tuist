import Foundation
import Path
import TuistCache
import TuistCore

/// Empty `CacheStoring` implementation as we noop cache storing in the opensource repository
public final class EmptyCacheStorage: CacheStoring {
    public init() {}

    public func fetch(
        _: Set<CacheStorableItem>,
        cacheCategory _: RemoteCacheCategory
    ) async throws -> [CacheItem: AbsolutePath] {
        [:]
    }

    public func store(_: [CacheStorableItem: [AbsolutePath]], cacheCategory _: RemoteCacheCategory)
        async throws
    {}
}
