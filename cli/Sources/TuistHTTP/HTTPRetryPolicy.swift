import Foundation
import TuistEnvironment

public struct HTTPRetryPolicy: Sendable {
    public static let defaultMaximumRetryCount = 3
    public static let defaultBaseDelayMilliseconds: UInt64 = 100
    static let maximumRetryCountLimit = 10
    static let maximumDelayMilliseconds: UInt64 = 30000

    private static let nanosecondsPerMillisecond: UInt64 = 1_000_000

    public let maximumRetryCount: Int
    public let baseDelayMilliseconds: UInt64

    public init(
        maximumRetryCount: Int? = nil,
        baseDelayMilliseconds: UInt64? = nil,
        environment: [String: String] = Environment.current.variables
    ) {
        let resolvedMaximumRetryCount = maximumRetryCount ?? Self.maximumRetryCount(environment: environment)
        let resolvedBaseDelayMilliseconds = baseDelayMilliseconds ?? Self.baseDelayMilliseconds(environment: environment)

        self.maximumRetryCount = min(max(0, resolvedMaximumRetryCount), Self.maximumRetryCountLimit)
        self.baseDelayMilliseconds = min(resolvedBaseDelayMilliseconds, Self.maximumDelayMilliseconds)
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

    private static func maximumRetryCount(environment: [String: String]) -> Int {
        guard let value = environment["TUIST_HTTP_MAXIMUM_RETRY_COUNT"],
              let maximumRetryCount = Int(value),
              maximumRetryCount >= 0
        else {
            return defaultMaximumRetryCount
        }
        return maximumRetryCount
    }

    private static func baseDelayMilliseconds(environment: [String: String]) -> UInt64 {
        guard let value = environment["TUIST_HTTP_RETRY_BASE_DELAY_IN_MILLISECONDS"],
              let baseDelayMilliseconds = UInt64(value)
        else {
            return defaultBaseDelayMilliseconds
        }
        return baseDelayMilliseconds
    }
}
