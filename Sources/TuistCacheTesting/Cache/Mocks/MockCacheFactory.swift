import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
@testable import TuistCache

public final class MockCacheFactory: CacheFactoring {
    public var cacheStub: (([CacheStoring]) -> CacheStoring)?

    public func cache(storages: [CacheStoring]) -> CacheStoring {
        cacheStub?(storages) ?? MockCacheStorage()
    }
}
