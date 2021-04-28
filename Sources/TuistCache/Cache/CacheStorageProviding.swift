import Foundation
import TuistCore
import TuistGraph

/// It defines the interface to get the storages that should be used given a config.
public protocol CacheStorageProviding: AnyObject {
    init(config: Config)

    /// Given a configuration, it returns the storages that should be used.
    func storages() throws -> [CacheStoring]
}
