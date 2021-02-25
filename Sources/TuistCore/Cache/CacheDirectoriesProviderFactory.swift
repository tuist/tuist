import Foundation
import TuistGraph
import TuistSupport

public protocol CacheDirectoriesProviderFactoring {
    func cacheDirectories(config: Config?) throws -> CacheDirectoriesProviding
}

public final class CacheDirectoriesProviderFactory: CacheDirectoriesProviderFactoring {
    public init() {}
    public func cacheDirectories(config: Config?) throws -> CacheDirectoriesProviding {
        let provider = CacheDirectoriesProvider(config: config)
        try provider.cacheDirectories.forEach { directory in
            if !FileHandler.shared.exists(directory) {
                try FileHandler.shared.createFolder(directory)
            }
        }
        return provider
    }
}
