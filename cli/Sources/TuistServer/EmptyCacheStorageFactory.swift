#if canImport(TuistCore)
    import Foundation
    import TuistConfig
    import TuistCore

    public struct EmptyCacheStorageFactory: CacheStorageFactorying {
        public init() {}

        public func cacheStorage(config _: Tuist) throws -> any CacheStoring {
            EmptyCacheStorage()
        }

        public func cacheLocalStorage() throws -> any CacheStoring {
            EmptyCacheStorage()
        }
    }
#endif
