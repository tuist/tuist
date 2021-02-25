import Foundation
import TuistCache
import TuistCloud
import TuistCore
import TuistGraph
import TuistLoader

final class CacheStorageProvider: CacheStorageProviding {
    private let config: Config
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring

    init(config: Config) {
        self.config = config
        cacheDirectoryProviderFactory = CacheDirectoriesProviderFactory()
    }

    func storages() throws -> [CacheStoring] {
        let cacheDirectoriesProvider = try cacheDirectoryProviderFactory.cacheDirectories(config: config)
        var storages: [CacheStoring] = [CacheLocalStorage(cacheDirectoriesProvider: cacheDirectoriesProvider)]
        if let cloudConfig = config.cloud {
            let storage = CacheRemoteStorage(cloudConfig: cloudConfig, cloudClient: CloudClient(), cacheDirectoriesProvider: cacheDirectoriesProvider)
            storages.append(storage)
        }
        return storages
    }
}
