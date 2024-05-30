import Foundation
import Mockable
import TuistCore
import TuistGraph
import TuistSupport

@Mockable
public protocol CacheStorageFactorying {
    func cacheStorage(config: Config) throws -> CacheStoring
}
