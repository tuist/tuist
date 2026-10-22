import Foundation
import TuistEnvironment

public struct HTTPRetryPolicy: Sendable {
    /// Five attempts spread over roughly 200, 400, 800 and 1600 ms plus jitter, about three to four
    /// seconds in total, which covers the window in which a server rollout replaces its pods and
    /// the ingress answers 502/503 or refuses connections.
    public static let defaultMaximumRetryCount = 4
    public static let defaultBaseDelayMilliseconds: UInt64 = 200
    static let maximumRetryCountLimit = 10
    static let maximumDelayMilliseconds: UInt64 = 30000

    private static let nanosecondsPerMillisecond: UInt64 = 1_000_000

    public let maximumRetryCount: Int
    public let baseDelayMilliseconds: UInt64

    /// - Parameters:
    ///   - defaultMaximumRetryCount: The retry count used when neither `maximumRetryCount` nor
    ///     `TUIST_HTTP_MAXIMUM_RETRY_COUNT` sets one.
    ///   - defaultBaseDelayMilliseconds: The base delay used when neither `baseDelayMilliseconds`
    ///     nor `TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS` sets one.
    public init(
        maximumRetryCount: Int? = nil,
        baseDelayMilliseconds: UInt64? = nil,
        defaultMaximumRetryCount: Int = HTTPRetryPolicy.defaultMaximumRetryCount,
        defaultBaseDelayMilliseconds: UInt64 = HTTPRetryPolicy.defaultBaseDelayMilliseconds,
        environment: [String: String] = Environment.current.variables
    ) {
        let resolvedMaximumRetryCount = maximumRetryCount
            ?? Self.maximumRetryCount(environment: environment) ?? defaultMaximumRetryCount
        let resolvedBaseDelayMilliseconds = baseDelayMilliseconds
            ?? Self.baseDelayMilliseconds(environment: environment) ?? defaultBaseDelayMilliseconds

        self.maximumRetryCount = min(max(0, resolvedMaximumRetryCount), Self.maximumRetryCountLimit)
        self.baseDelayMilliseconds = min(resolvedBaseDelayMilliseconds, Self.maximumDelayMilliseconds)
    }

    /// 408 and 429 are the only 4xx statuses a server can resolve on its own, so every other
    /// one answers a repeated request the same way it answered the first.
    public static func isPermanentClientError(statusCode: Int) -> Bool {
        (400 ..< 500).contains(statusCode) && statusCode != 408 && statusCode != 429
    }

    public func delay(for retry: Int) -> UInt64 {
        let maximumDelayNanoseconds = Self.maximumDelayMilliseconds * Self.nanosecondsPerMillisecond
        let baseDelayNanoseconds = baseDelayMilliseconds * Self.nanosecondsPerMillisecond
        guard baseDelayNanoseconds > 0 else { return 0 }

        let exponent = max(0, retry)
        guard exponent < UInt64.bitWidth else { return maximumDelayNanoseconds }

        let exponentialDelay = baseDelayNanoseconds.multipliedReportingOverflow(by: UInt64(1) << exponent)
        guard !exponentialDelay.overflow,
              exponentialDelay.partialValue < maximumDelayNanoseconds
        else {
            return maximumDelayNanoseconds
        }

        let maximumJitter = min(
            baseDelayNanoseconds,
            maximumDelayNanoseconds - exponentialDelay.partialValue
        )
        let jitter = UInt64.random(in: 0 ... maximumJitter)
        return exponentialDelay.partialValue + jitter
    }

    private static func maximumRetryCount(environment: [String: String]) -> Int? {
        guard let value = environment["TUIST_HTTP_MAXIMUM_RETRY_COUNT"],
              let maximumRetryCount = Int(value),
              maximumRetryCount >= 0
        else {
            return nil
        }
        return maximumRetryCount
    }

    private static func baseDelayMilliseconds(environment: [String: String]) -> UInt64? {
        guard let value = environment["TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS"] else { return nil }
        return UInt64(value)
    }
}
