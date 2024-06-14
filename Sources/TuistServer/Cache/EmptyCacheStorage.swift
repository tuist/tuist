import Foundation
import Path
import TuistCore

/// Empty `CacheStoring` implementation as we noop cache storing in the opensource repository
public final class EmptyCacheStorage: CacheStoring {
    public init() {}

    public func fetch(
        _: Set<CacheStorableItem>,
        cacheCategory _: CacheCategory.App
    ) async throws -> [CacheStorableItem: AbsolutePath] {
        [:]
    }

    public func store(_: [CacheStorableItem: [AbsolutePath]], cacheCategory _: CacheCategory.App) async throws {}
}
