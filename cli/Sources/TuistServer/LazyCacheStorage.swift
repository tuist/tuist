#if canImport(TuistCore)
    import Foundation
    import Path
    import TuistCore

    private actor LazyCacheStorageResolver {
        private let makeStorage: @Sendable () async throws -> any CacheStoring
        private var storage: (any CacheStoring)?
        private var inFlightStorage: Task<any CacheStoring, Error>?

        init(makeStorage: @escaping @Sendable () async throws -> any CacheStoring) {
            self.makeStorage = makeStorage
        }

        func fetch(
            _ items: Set<CacheStorableItem>,
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheItem: AbsolutePath] {
            let storage = try await resolveStorage()
            return try await storage.fetch(items, cacheCategory: cacheCategory)
        }

        func store(
            _ items: [CacheStorableItem: [AbsolutePath]],
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheStorableItem] {
            let storage = try await resolveStorage()
            return try await storage.store(items, cacheCategory: cacheCategory)
        }

        private func resolveStorage() async throws -> any CacheStoring {
            if let storage {
                return storage
            }

            if let inFlightStorage {
                return try await inFlightStorage.value
            }

            let task = Task {
                try await makeStorage()
            }
            inFlightStorage = task

            do {
                let storage = try await task.value
                self.storage = storage
                inFlightStorage = nil
                return storage
            } catch {
                inFlightStorage = nil
                throw error
            }
        }
    }

    public struct LazyCacheStorage: CacheStoring {
        private let resolver: LazyCacheStorageResolver

        public init(makeStorage: @escaping @Sendable () async throws -> any CacheStoring) {
            resolver = LazyCacheStorageResolver(makeStorage: makeStorage)
        }

        public func fetch(
            _ items: Set<CacheStorableItem>,
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheItem: AbsolutePath] {
            try await resolver.fetch(items, cacheCategory: cacheCategory)
        }

        public func store(
            _ items: [CacheStorableItem: [AbsolutePath]],
            cacheCategory: RemoteCacheCategory
        ) async throws -> [CacheStorableItem] {
            try await resolver.store(items, cacheCategory: cacheCategory)
        }
    }
#endif
