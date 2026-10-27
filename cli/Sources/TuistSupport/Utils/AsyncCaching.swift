import Foundation

/// Caches the first realized value, coalescing concurrent callers onto a single build.
///
/// `AsyncThrowableCaching` is the same cache for builders that throw. They can't be one generic
/// actor over the failure type because `Task` is only constructible with `Never` or `any Error`.
actor AsyncCaching<T: Sendable> {
    private var cachedValue: T?
    private var inFlightTask: Task<T, Never>?
    private let builder: @Sendable () async -> T

    init(_ builder: @Sendable @escaping () async -> T) {
        self.builder = builder
    }

    func value() async -> T {
        if let cachedValue {
            return cachedValue
        }
        // Coalesce concurrent first-callers onto a single task. Storing the task synchronously
        // (before any suspension point) ensures callers that arrive while the builder is running
        // await the same result instead of each kicking off a duplicate `builder()`.
        if let inFlightTask {
            return await inFlightTask.value
        }
        let task = Task { await builder() }
        inFlightTask = task
        let realizedValue = await task.value
        cachedValue = realizedValue
        inFlightTask = nil
        return realizedValue
    }
}

actor AsyncThrowableCaching<T: Sendable> {
    private var cachedValue: T?
    private var inFlightTask: Task<T, Error>?
    private let builder: @Sendable () async throws -> T

    init(_ builder: @Sendable @escaping () async throws -> T) {
        self.builder = builder
    }

    func value() async throws -> T {
        if let cachedValue {
            return cachedValue
        }
        if let inFlightTask {
            return try await inFlightTask.value
        }
        let task = Task { try await builder() }
        inFlightTask = task
        do {
            let realizedValue = try await task.value
            cachedValue = realizedValue
            inFlightTask = nil
            return realizedValue
        } catch {
            inFlightTask = nil
            throw error
        }
    }
}
