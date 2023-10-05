import TuistCloud
import TuistGraph

public final class MockCacheStorageProvider: CacheStorageProviding {
    var storagesStub: [CacheStoring]

    public init(config _: Config) {
        storagesStub = []
    }

    public func storages() throws -> [CacheStoring] {
        storagesStub
    }
}
