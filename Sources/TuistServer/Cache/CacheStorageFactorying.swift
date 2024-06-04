import Foundation
import Mockable
import TuistCore
import XcodeProjectGenerator
import TuistSupport

@Mockable
public protocol CacheStorageFactorying {
    func cacheStorage(config: Config) throws -> CacheStoring
}
