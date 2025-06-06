import Foundation
import Mockable

@Mockable
/// Actor that caches a piece of work asynchronously in a thread-safe manner.
protocol CachedValueStoring: Sendable {
    func getValue<Value>(key: String, computeIfNeeded: @escaping () async throws -> Value) async throws -> Value
}

actor CachedValueStore: CachedValueStoring {
    static let shared = CachedValueStore()

    private var tasks: [String: Task<Any, any Error>] = [:]

    func getValue<Value>(key: String, computeIfNeeded: @escaping () async throws -> Value) async throws -> Value {
        if tasks[key] == nil {
            tasks[key] = Task {
                defer { tasks[key] = nil }
                return try await computeIfNeeded()
            }
        }
        // swiftlint:disable:next force_unwrapping, force_cast
        return try await tasks[key]!.value as! Value
    }
}
