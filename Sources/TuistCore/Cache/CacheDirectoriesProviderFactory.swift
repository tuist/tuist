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
        for category in CacheCategory.allCases {
            let directory = provider.cacheDirectory(for: category)
            if !FileHandler.shared.exists(directory) {
                try FileHandler.shared.createFolder(directory)
            }
        }
        return provider
    }
}
