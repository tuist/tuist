#if canImport(TuistCore)
    import Foundation
    import Mockable
    import TuistCore

    @Mockable
    public protocol CacheStorageFactorying {
        func cacheStorage(config: Tuist) async throws -> CacheStoring
        /// - Returns: Cache storage that only works with the local cache.
        func cacheLocalStorage() async throws -> CacheStoring
    }
#endif
