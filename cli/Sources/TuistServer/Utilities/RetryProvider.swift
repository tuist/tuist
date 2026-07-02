import Foundation
import Logging

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
        let maxRetryCount = 3
        for retry in 0 ..< maxRetryCount {
            try Task<Never, Never>.checkCancellation()
            do {
                return try await operation()
            } catch let error as CancellationError {
                throw error
            } catch {
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
