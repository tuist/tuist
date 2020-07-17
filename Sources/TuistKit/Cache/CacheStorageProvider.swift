import Foundation
import TuistCache
import TuistCore
import TuistScale

final class CacheStorageProvider: CacheStorageProviding {
    let config: Config

    init(config: Config) {
        self.config = config
    }

    func storages() -> [CacheStoring] {
        var storages: [CacheStoring] = [CacheLocalStorage()]
        if let scaleConfig = config.scale {
            let storage = CacheRemoteStorage(scaleConfig: scaleConfig, scaleClient: ScaleClient())
            storages.append(storage)
        }
        return storages
    }
}
