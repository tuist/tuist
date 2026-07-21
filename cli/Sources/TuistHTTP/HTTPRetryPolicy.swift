import Foundation
import TuistEnvironment

public struct HTTPRetryPolicy: Sendable {
    public static let defaultMaximumRetryCount = 3
    public static let defaultBaseDelayMilliseconds: UInt64 = 100

    public let maximumRetryCount: Int
    public let baseDelayMilliseconds: UInt64

    public init(
        maximumRetryCount: Int? = nil,
        baseDelayMilliseconds: UInt64? = nil,
        environment: [String: String] = Environment.current.variables
    ) {
        let resolvedMaximumRetryCount = maximumRetryCount ?? Self.maximumRetryCount(environment: environment)
        let resolvedBaseDelayMilliseconds = baseDelayMilliseconds ?? Self.baseDelayMilliseconds(environment: environment)

        self.maximumRetryCount = max(0, resolvedMaximumRetryCount)
        self.baseDelayMilliseconds = Self.validatedBaseDelayMilliseconds(resolvedBaseDelayMilliseconds)
    }

    public func delay(for retry: Int) -> UInt64 {
        let baseDelayNanoseconds = baseDelayMilliseconds * 1_000_000
        guard baseDelayNanoseconds > 0 else { return 0 }

        let exponent = max(0, retry)
        guard exponent < UInt64.bitWidth else { return .max }

        let exponentialDelay = baseDelayNanoseconds.multipliedReportingOverflow(by: UInt64(1) << exponent)
        guard !exponentialDelay.overflow else { return .max }

        let jitter = UInt64.random(in: 0 ... baseDelayNanoseconds)
        let delay = exponentialDelay.partialValue.addingReportingOverflow(jitter)
        return delay.overflow ? .max : delay.partialValue
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

    private static func validatedBaseDelayMilliseconds(_ baseDelayMilliseconds: UInt64) -> UInt64 {
        let nanoseconds = baseDelayMilliseconds.multipliedReportingOverflow(by: 1_000_000)
        return nanoseconds.overflow ? defaultBaseDelayMilliseconds : baseDelayMilliseconds
    }
}
