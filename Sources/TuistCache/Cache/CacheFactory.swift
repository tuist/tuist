import Foundation
import TuistGraph
import TuistSupport

public protocol CacheFactoring {
    func cache(storages: [CacheStoring]) -> CacheStoring
}

public final class CacheFactory: CacheFactoring {
    public init() {}
    public func cache(storages: [CacheStoring]) -> CacheStoring {
        Cache(storages: storages)
    }
}
