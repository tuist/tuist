import TuistCache
import TuistCore
import TuistGraph

public final class MockCacheStorageProvider: CacheStorageProviding {
    var storagesStub: [CacheStoring]

    public init(config _: Config, cacheDownloaderType _: CacheDownloaderType) {
        storagesStub = []
    }

    public func storages() throws -> [CacheStoring] {
        storagesStub
    }
}
