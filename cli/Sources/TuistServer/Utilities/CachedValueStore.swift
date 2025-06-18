import Foundation
import Mockable

@Mockable
/// Actor that caches a piece of work asynchronously in a thread-safe manner.
protocol CachedValueStoring: Sendable {
    func getValue<Value>(
        key: String,
        computeIfNeeded: @escaping () async throws -> (value: Value, expiresAt: Date?)?
    ) async throws -> Value?
}

actor CachedValueStore: CachedValueStoring {
    static let shared = CachedValueStore()

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

    func getValue<Value>(
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

        // Wait for the task to complete and return its value
        // swiftlint:disable:next force_unwrapping, force_cast
        return try await tasks[key]?.value as? Value
    }
}
