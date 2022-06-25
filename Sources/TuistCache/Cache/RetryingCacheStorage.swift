import TSCBasic

/// A wrapper for `CacheStoring` that retries API call once on failure
public final class RetryingCacheStorage: CacheStoring {
    // MARK: - Attributes

    private let cacheStoring: CacheStoring

    // MARK: - Init

    public init(cacheStoring: CacheStoring) {
        self.cacheStoring = cacheStoring
    }

    public func exists(name: String, hash: String) async throws -> Bool {
        try await retryOnceOnError(label: "exists", name: name, hash: hash) {
            return try await cacheStoring.exists(name: name, hash: hash)
        }
    }

    public func fetch(name: String, hash: String) async throws -> AbsolutePath {
        try await retryOnceOnError(label: "fetch", name: name, hash: hash) {
            return try await cacheStoring.fetch(name: name, hash: hash)
        }
    }

    public func store(name: String, hash: String, paths: [AbsolutePath]) async throws {
        try await retryOnceOnError(label: "store", name: name, hash: hash) { () -> Void in
            return try await cacheStoring.store(name: name, hash: hash, paths: paths)
        }
    }

    private func retryOnceOnError<T>(label: String, name: String, hash: String, _ closure: () async throws -> T) async throws -> T {
        do {
            return try await closure()
        } catch {
            logger.warning("Retrying failed `\(label)` for target \(name) with hash \(hash)")
            return try await closure()
        }
    }
}
