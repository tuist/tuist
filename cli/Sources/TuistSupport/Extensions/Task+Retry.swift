import Foundation

// Inspired by https://www.swiftbysundell.com/articles/retrying-an-async-swift-task/

extension Task where Failure == Error {
    @discardableResult
    public static func retrying(
        priority: TaskPriority? = nil,
        maxRetryCount: Int = 3,
        operation: @Sendable @escaping () async throws -> Success
    ) -> Task {
        Task(priority: priority) {
            for _ in 0 ..< maxRetryCount {
                do {
                    return try await operation()
                } catch {
                    continue
                }
            }

            try Task<Never, Never>.checkCancellation()
            return try await operation()
        }
    }
}
