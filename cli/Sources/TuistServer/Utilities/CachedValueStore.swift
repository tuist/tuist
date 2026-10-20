import Foundation
import Mockable

#if !os(iOS)
    import FileSystem
    import Path
    import TSCBasic
    import TuistEnvironment
    import TuistLogging
#endif

public enum CachedValueStoreBackend: Sendable {
    #if !os(iOS)
        case fileSystem
    #endif
    case inSystemProcess
}

/// Thrown when the file-system-backed cache cannot acquire its cross-process
/// lock within the configured wall-clock ceiling. Wrapping `flock()` in a
/// bounded polling loop turns "a peer holds the lock and never releases it"
/// from a silent, uncancellable stall into a clear error the caller can retry.
public struct CachedValueStoreFileLockTimeoutError: LocalizedError, Sendable {
    public let seconds: TimeInterval

    public var errorDescription: String? {
        "Timed out after \(Int(seconds))s waiting to acquire the cached-value-store file lock. Another Tuist process may be holding it."
    }
}

/// Actor that caches a piece of work asynchronously in a thread-safe manner.
@Mockable
public protocol CachedValueStoring: Sendable {
    func getValue<Value>(
        key: String,
        computeIfNeeded: @escaping () async throws -> (value: Value, expiresAt: Date?)?
    ) async throws -> Value?
}

public actor CachedValueStore: CachedValueStoring {
    #if !os(iOS)
        @TaskLocal public static var current: CachedValueStoring = CachedValueStore(backend: .fileSystem)
    #else
        @TaskLocal public static var current: CachedValueStoring = CachedValueStore(backend: .inSystemProcess)
    #endif

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

    #if !os(iOS)
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

        /// Wall-clock ceiling for acquiring the cross-process file lock.
        /// A peer `tuist` process that holds the lock while its own work
        /// stalls (e.g. a slow HTTPS refresh on a flaky Linux runner) would
        /// otherwise block every subsequent invocation on this host forever.
        private static let fileLockAcquisitionTimeout: TimeInterval = 30

        /// Interval between non-blocking `flock` attempts. Kept short enough
        /// that a well-behaved peer that releases quickly barely notices,
        /// long enough that the polling cost is negligible.
        private static let fileLockRetryInterval: TimeInterval = 0.1

        /// Acquires `fileLock` with a bounded wall-clock timeout by polling
        /// its non-blocking variant with backoff. `TSCBasic.FileLock` wraps
        /// `flock(_:LOCK_EX)`, which is not cancellable via Swift Concurrency
        /// and does not honour any deadline; using `blocking: false` in a
        /// timed loop is the only way to bound it. On acquisition the caller
        /// is responsible for calling `fileLock.unlock()` (typically via
        /// `defer`).
        static func acquireFileLockWithTimeout(
            _ fileLock: FileLock,
            timeout: TimeInterval = CachedValueStore.fileLockAcquisitionTimeout,
            retryInterval: TimeInterval = CachedValueStore.fileLockRetryInterval
        ) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                do {
                    try fileLock.lock(type: .exclusive, blocking: false)
                    return
                } catch ProcessLockError.unableToAquireLock {
                    if Date() >= deadline {
                        throw CachedValueStoreFileLockTimeoutError(seconds: timeout)
                    }
                    try await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
                }
            }
        }
    #endif

    public func getValue<Value>(
        key: String,
        computeIfNeeded: @escaping () async throws -> (value: Value, expiresAt: Date?)?
    ) async throws -> Value? {
        #if !os(iOS)
            Logger.current.debug("Getting cached value for \(key)")
        #endif
        // Check if we have a cached value that isn't expired
        if let cacheEntry = cache[key] as? CacheEntry<Value>, !cacheEntry.isExpired {
            #if !os(iOS)
                Logger.current.debug("\(key) is cached and not expired")
            #endif
            return cacheEntry.value
        }

        // If there's no valid cache entry, create or reuse a task
        // Capture task reference locally to avoid race condition where task completes
        // and clears tasks[key] before we can await it
        let task: Task<Any?, any Error>
        if let existingTask = tasks[key] {
            #if !os(iOS)
                Logger.current
                    .debug("\(key)'s value is already being computed from a different thread, waiting for it to complete...")
            #endif
            task = existingTask
        } else {
            let newTask = Task<Any?, any Error> {
                #if !os(iOS)
                    Logger.current.debug("Triggered a new task to compute value for \(key)")
                #endif
                defer { tasks[key] = nil }

                switch backend {
                #if !os(iOS)
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

                        try await Self.acquireFileLockWithTimeout(fileLock)
                        defer { fileLock.unlock() }

                        // Double-check cache after acquiring lock
                        // Another process might have computed the value
                        if let cacheEntry = cache[key] as? CacheEntry<Value>, !cacheEntry.isExpired {
                            Logger.current
                                .debug(
                                    "The value for \(key) has been computed from a different process, returning its value early"
                                )
                            return cacheEntry.value
                        }

                        Logger.current.debug("Computing the value for \(key) if needed")
                        if let result = try await computeIfNeeded() {
                            let value = result.value
                            let expirationDate = result.expiresAt

                            // Store in cache
                            let entry = CacheEntry(value: value, expirationDate: expirationDate)
                            cache[key] = entry

                            Logger.current.debug("Computed value for \(key)")
                            return value
                        } else {
                            Logger.current.debug("Computed value for \(key) is nil")
                            return nil
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
            tasks[key] = newTask
            task = newTask
        }

        // Wait for the task to complete and return its value
        let value = try await task.value as? Value
        #if !os(iOS)
            Logger.current.debug("Returning value for \(key)")
        #endif
        return value
    }

    #if DEBUG
        public static var mocked: MockCachedValueStoring? { current as? MockCachedValueStoring }
    #endif
}
