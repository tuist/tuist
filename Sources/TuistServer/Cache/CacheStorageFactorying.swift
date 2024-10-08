import Foundation
import Mockable
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol CacheStorageFactorying {
    func cacheStorage(config: Config) async throws -> CacheStoring
}
