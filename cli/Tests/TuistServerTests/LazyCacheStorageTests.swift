import Foundation
import Path
import Testing

@testable import TuistCore
@testable import TuistServer

struct LazyCacheStorageTests {
    @Test func initializes_storage_once_for_concurrent_first_fetches() async throws {
        let factory = StorageFactoryCounter()
        let subject = LazyCacheStorage {
            await factory.makeStorage()
        }
        let item = CacheStorableItem(name: "Framework", hash: "hash")

        async let first = subject.fetch([item], cacheCategory: .binaries)
        async let second = subject.fetch([item], cacheCategory: .binaries)

        _ = try await (first, second)

        let initializationCount = await factory.initializationCount
        #expect(initializationCount == 1)
    }
}

private actor StorageFactoryCounter {
    private(set) var initializationCount = 0

    func makeStorage() -> any CacheStoring {
        initializationCount += 1
        return StubCacheStorage()
    }
}

private struct StubCacheStorage: CacheStoring {
    func fetch(
        _ items: Set<CacheStorableItem>,
        cacheCategory: RemoteCacheCategory
    ) async throws -> [CacheItem: AbsolutePath] {
        Dictionary(
            uniqueKeysWithValues: items.map {
                (
                    CacheItem(
                        name: $0.name,
                        hash: $0.hash,
                        source: .local,
                        cacheCategory: cacheCategory
                    ),
                    AbsolutePath.root.appending(component: $0.name)
                )
            }
        )
    }

    func store(
        _ items: [CacheStorableItem: [AbsolutePath]],
        cacheCategory _: RemoteCacheCategory
    ) async throws -> [CacheStorableItem] {
        Array(items.keys)
    }
}
