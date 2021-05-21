import Foundation
import TuistCache
import TuistCore
import TuistGraph
import TuistLab
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
        if let labConfig = config.lab {
            let storage = CacheRemoteStorage(
                labConfig: labConfig,
                labClient: LabClient(),
                cacheDirectoriesProvider: cacheDirectoriesProvider
            )
            storages.append(storage)
        }
        return storages
    }
}
