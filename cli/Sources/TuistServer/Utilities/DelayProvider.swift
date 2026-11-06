import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol DelayProviding {
    func delay(for retry: Int) -> UInt64
}

public struct DelayProvider: DelayProviding {
    /// The base delay `RetryProvider` backs off from, shorter than `HTTPRetryPolicy`'s for the same reason as
    /// `RetryProvider.defaultMaximumRetryCount`.
    public static let defaultBaseDelayMilliseconds: UInt64 = 100

    private let retryPolicy: HTTPRetryPolicy

    public init(baseDelayMilliseconds: UInt64? = nil) {
        retryPolicy = HTTPRetryPolicy(
            baseDelayMilliseconds: baseDelayMilliseconds,
            defaultBaseDelayMilliseconds: Self.defaultBaseDelayMilliseconds
        )
    }

    public func delay(for retry: Int) -> UInt64 {
        retryPolicy.delay(for: retry)
    }
}
