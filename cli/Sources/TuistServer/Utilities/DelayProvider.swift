import Foundation
import Mockable
import TuistHTTP

@Mockable
public protocol DelayProviding {
    func delay(for retry: Int) -> UInt64
}

public struct DelayProvider: DelayProviding {
    private let retryPolicy: HTTPRetryPolicy

    public init(baseDelayMilliseconds: UInt64? = nil) {
        retryPolicy = HTTPRetryPolicy(baseDelayMilliseconds: baseDelayMilliseconds)
    }

    public func delay(for retry: Int) -> UInt64 {
        retryPolicy.delay(for: retry)
    }
}
