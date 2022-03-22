import Foundation
import TSCBasic
import TuistCore

public final class Cache: CacheStoring {
    // MARK: - Attributes

    private let storages: [CacheStoring]

    // MARK: - Init

    /// Initializes the cache with its attributes.
    /// - Parameter storages: List of storages for retrieving and saving items.
    public init(storages: [CacheStoring]) {
        self.storages = storages
    }

    // MARK: - CacheStoring

    public func exists(name: String, hash: String) async throws -> Bool {
        for storage in storages {
            if try await storage.exists(name: name, hash: hash) {
                return true
            }
        }
        return false
    }

    public func fetch(name: String, hash: String) async throws -> AbsolutePath {
        var throwingError: Error = CacheLocalStorageError.compiledArtifactNotFound(hash: hash)
        for storage in storages {
            do {
                return try await storage.fetch(name: name, hash: hash)
            } catch {
                throwingError = error
                continue
            }
        }
        throw throwingError
    }

    public func store(name: String, hash: String, paths: [AbsolutePath]) async throws {
        _ = try await storages.concurrentMap { storage in
            try await storage.store(name: name, hash: hash, paths: paths)
        }
    }
}
