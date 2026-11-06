import Foundation
import Logging
import TuistHTTP

public protocol RetryProviding {
    func runWithRetries<T>(
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T
}

public struct RetryProvider: RetryProviding {
    /// Wrapped operations often send requests that `RetryMiddleware` already retries, so this layer keeps
    /// a shorter ladder than `HTTPRetryPolicy` to bound the attempts the two multiply into.
    public static let defaultMaximumRetryCount = 3

    private let delayProvider: DelayProviding
    private let maximumRetryCount: Int

    public init(
        maximumRetryCount: Int? = nil,
        delayProvider: DelayProviding = DelayProvider()
    ) {
        self.maximumRetryCount = HTTPRetryPolicy(
            maximumRetryCount: maximumRetryCount,
            defaultMaximumRetryCount: Self.defaultMaximumRetryCount
        ).maximumRetryCount
        self.delayProvider = delayProvider
    }

    public func runWithRetries<T>(
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        for retry in 0 ..< maximumRetryCount {
            try Task<Never, Never>.checkCancellation()
            do {
                return try await operation()
            } catch let error as CancellationError {
                throw error
            } catch {
                guard ServerErrorClassifier.isRetryable(error) else { throw error }

                #if canImport(TuistSupport)
                    Logger.current.debug("""
                    The following error happened for retry \(retry): \(error.localizedDescription).
                    Retrying...
                    """)
                #endif
                try await Task<Never, Never>.sleep(nanoseconds: delayProvider.delay(for: retry))
            }
        }

        try Task<Never, Never>.checkCancellation()
        return try await operation()
    }
}
