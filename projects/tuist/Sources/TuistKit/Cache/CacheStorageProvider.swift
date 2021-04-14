import Foundation
import TuistCache
import TuistCloud
import TuistCore
import TuistGraph

final class CacheStorageProvider: CacheStorageProviding {
    let config: Config

    init(config: Config) {
        self.config = config
    }

    func storages() -> [CacheStoring] {
        var storages: [CacheStoring] = [CacheLocalStorage()]
        if let cloudConfig = config.cloud {
            let storage = CacheRemoteStorage(cloudConfig: cloudConfig, cloudClient: CloudClient())
            storages.append(storage)
        }
        return storages
    }
}
