import Foundation
import GRPCCore
import GRPCProtobuf
import Synchronization

/// Upload admission needs time for other transfers to release memory. Reads keep their short
/// retry policy so overload doesn't stall generation. Neither policy retries before a server's
/// minimum delay: a hint that exceeds the remaining wait budget causes failure instead.
public struct REAPIBackpressureRetryPolicy: Sendable {
    public let maximumRetryCount: Int
    public let baseDelayMilliseconds: Int64
    /// Total scheduled backoff shared by the calls in a blob-upload operation, not a transfer deadline.
    public let maximumCumulativeDelay: Duration
    private static let maximumDelayMilliseconds: Int64 = 30000

    public init(
        maximumRetryCount: Int = 6,
        baseDelayMilliseconds: Int64 = 1000,
        maximumCumulativeDelay: Duration = .seconds(60)
    ) {
        self.maximumRetryCount = min(max(maximumRetryCount, 0), 10)
        self.baseDelayMilliseconds = min(max(baseDelayMilliseconds, 0), Self.maximumDelayMilliseconds)
        self.maximumCumulativeDelay = max(maximumCumulativeDelay, .zero)
    }

    func delay(for retry: Int, error: RPCError) -> Duration {
        let exponential = min(
            baseDelayMilliseconds * (Int64(1) << min(max(0, retry), 10)),
            Self.maximumDelayMilliseconds
        )
        let backoff = Duration.milliseconds(exponential) * Double.random(in: 0.8 ... 1.2)
        guard let hinted = Self.retryInfoDelay(error) else { return backoff }
        // Avoid scaling an arbitrarily large, valid hint. The caller will decline this retry
        // because it cannot fit the budget, rather than shorten the server's minimum delay.
        guard hinted <= maximumCumulativeDelay else { return hinted }
        return max(backoff, hinted * Double.random(in: 1.0 ... 1.2))
    }

    static func retryInfoDelay(_ error: RPCError) -> Duration? {
        guard let status = try? error.unpackGoogleRPCStatus(), status.code == .resourceExhausted,
              let delay = status.details.lazy.compactMap(\.retryInfo).first?.delay, delay >= .zero
        else { return nil }
        return delay
    }
}

/// Share scheduled backoff across all calls in one upload operation. Concurrent waits each
/// consume the budget, but successful transfers never do: this is not a transfer deadline.
final class REAPIUploadRetryBudget: Sendable {
    private let remaining: Mutex<Duration>

    init(maximumDelay: Duration) {
        remaining = Mutex(max(maximumDelay, .zero))
    }

    func consume(_ delay: Duration) -> Bool {
        remaining.withLock {
            guard delay >= .zero, delay <= $0 else { return false }
            $0 -= delay
            return true
        }
    }
}
