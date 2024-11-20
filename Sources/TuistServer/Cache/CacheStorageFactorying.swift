import Foundation
import Mockable
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheStorageFactorying {
    func cacheStorage(config: Config) async throws -> CacheStoring
    /// - Returns: Cache storage that only works with the local cache.
    func cacheLocalStorage() async throws -> CacheStoring
}
