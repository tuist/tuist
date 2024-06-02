import Foundation

public protocol RetryProviding {
    func runWithRetries<T>(
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T
}

public struct RetryProvider: RetryProviding {
    private let delayProvider: DelayProviding

    public init(
        delayProvider: DelayProviding = DelayProvider()
    ) {
        self.delayProvider = delayProvider
    }

    public func runWithRetries<T>(
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await Task {
            let maxRetryCount = 3
            for retry in 0 ..< maxRetryCount {
                do {
                    return try await operation()
                } catch {
                    logger.debug("""
                    The following error happened for retry \(retry): \(error.localizedDescription).
                    Retrying...
                    """)
                    try await Task<Never, Never>.sleep(nanoseconds: delayProvider.delay(for: retry))

                    continue
                }
            }

            try Task<Never, Never>.checkCancellation()
            return try await operation()
        }
        .value
    }
}
