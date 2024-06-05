import Foundation
import XcodeGraph

public final class EmptyCacheStorageFactory: CacheStorageFactorying {
    public init() {}

    public func cacheStorage(config _: Config) throws -> any CacheStoring {
        EmptyCacheStorage()
    }
}
