#if canImport(TuistCore)
    import Foundation
    import TuistCore

    public final class EmptyCacheStorageFactory: CacheStorageFactorying {
        public init() {}

        public func cacheStorage(config _: Tuist) throws -> any CacheStoring {
            EmptyCacheStorage()
        }

        public func cacheLocalStorage() throws -> any CacheStoring {
            EmptyCacheStorage()
        }
    }
#endif
