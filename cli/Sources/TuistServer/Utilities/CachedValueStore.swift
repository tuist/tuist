import Foundation
import Mockable

#if canImport(TuistSupport) && !os(iOS)
    import FileSystem
    import Path
    import TSCBasic
    import TuistSupport
#endif

public enum CachedValueStoreBackend: Sendable {
    #if os(macOS) || os(Linux) || os(Windows)
        case fileSystem
    #endif
    case inSystemProcess
}

@Mockable
/// Actor that caches a piece of work asynchronously in a thread-safe manner.
public protocol CachedValueStoring: Sendable {
    func getValue<Value>(
        key: String,
        computeIfNeeded: @escaping () async throws -> (value: Value, expiresAt: Date?)?
    ) async throws -> Value?
}

public actor CachedValueStore: CachedValueStoring {
    @TaskLocal public static var current: CachedValueStoring = CachedValueStore()

    private let backend: CachedValueStoreBackend

    public init(backend: CachedValueStoreBackend = .inSystemProcess) {
        self.backend = backend
    }

    private struct CacheEntry<T> {
        let value: T
        let expirationDate: Date?

        var isExpired: Bool {
            guard let expirationDate else {
                return false
            }
            return Date() >= expirationDate
        }
    }

    private var tasks: [String: Task<Any?, any Error>] = [:]
    private var cache: [String: Any] = [:]

    #if canImport(TuistSupport) && !os(iOS)
        private let fileSystem = FileSystem()

        /// Returns the path to the lock file for a given key
        private func lockFilePath(for key: String) -> Path.AbsolutePath {
            // Use a sanitized version of the key for the filename
            let sanitizedKey = key.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .replacingOccurrences(of: " ", with: "_")

            return Environment.current.stateDirectory
                .appending(component: "cached_value_store")
                .appending(component: "\(sanitizedKey).lock")
        }
    #endif

    public func getValue<Value>(
        key: String,
        computeIfNeeded: @escaping () async throws -> (value: Value, expiresAt: Date?)?
    ) async throws -> Value? {
        // Check if we have a cached value that isn't expired
        if let cacheEntry = cache[key] as? CacheEntry<Value>, !cacheEntry.isExpired {
            return cacheEntry.value
        }

        // If there's no valid cache entry, create or reuse a task
        if tasks[key] == nil {
            tasks[key] = Task {
                defer { tasks[key] = nil }

                switch backend {
                #if os(macOS) || os(Linux) || os(Windows)
                    case .fileSystem:
                        // Use file-based lock for cross-process synchronization
                        let lockPath = lockFilePath(for: key)

                        // Ensure the directory exists
                        let lockDirectory = lockPath.parentDirectory
                        if !(try await fileSystem.exists(lockPath.parentDirectory)) {
                            try await fileSystem.makeDirectory(at: lockDirectory)
                        }

                        let fileLock = FileLock(
                            at: try TSCBasic.AbsolutePath(validating: lockPath.pathString)
                        )

                        return try await fileLock.withLock(type: .exclusive) {
                            // Double-check cache after acquiring lock
                            // Another process might have computed the value
                            if let cacheEntry = cache[key] as? CacheEntry<Value>, !cacheEntry.isExpired {
                                return cacheEntry.value
                            }

                            if let result = try await computeIfNeeded() {
                                let value = result.value
                                let expirationDate = result.expiresAt

                                // Store in cache
                                let entry = CacheEntry(value: value, expirationDate: expirationDate)
                                cache[key] = entry

                                return value
                            } else {
                                return nil
                            }
                        }
                #endif
                case .inSystemProcess:
                    // Use actor isolation for in-system-process synchronization
                    if let cacheEntry = cache[key] as? CacheEntry<Value>, !cacheEntry.isExpired {
                        return cacheEntry.value
                    }

                    // Compute the value
                    if let result = try await computeIfNeeded() {
                        let value = result.value
                        let expirationDate = result.expiresAt

                        // Store in cache
                        let entry = CacheEntry(value: value, expirationDate: expirationDate)
                        cache[key] = entry

                        return value
                    } else {
                        return nil
                    }
                }
            }
        }

        // Wait for the task to complete and return its value
        // swiftlint:disable:next force_unwrapping, force_cast
        return try await tasks[key]!.value as? Value
    }
}

#if DEBUG
    extension CachedValueStore {
        public static var mocked: MockCachedValueStoring? { current as? MockCachedValueStoring }
    }
#endif
