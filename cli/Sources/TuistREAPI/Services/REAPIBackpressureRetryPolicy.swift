import Foundation
import GRPCCore
import SwiftProtobuf

/// Upload admission needs time for other transfers to release memory. Reads keep their short
/// retry policy so overload doesn't stall generation. Neither policy retries before a server's
/// minimum delay: a hint that exceeds the remaining wait budget causes failure instead.
public struct REAPIBackpressureRetryPolicy: Sendable {
    public let maximumRetryCount: Int
    public let baseDelayMilliseconds: Int64
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
        for bytes in error.metadata[binaryValues: "grpc-status-details-bin"] {
            guard let status = try? Google_Rpc_Status(serializedBytes: bytes), status.code == 8 else { continue }
            for detail in status.details where detail.typeURL.split(separator: "/").last == "google.rpc.RetryInfo" {
                guard let retry = try? Google_Rpc_RetryInfo(serializedBytes: detail.value), retry.hasRetryDelay,
                      retry.retryDelay.seconds >= 0,
                      (0 ..< 1_000_000_000).contains(retry.retryDelay.nanos)
                else { continue }
                return .seconds(retry.retryDelay.seconds) + .nanoseconds(Int64(retry.retryDelay.nanos))
            }
        }
        return nil
    }
}
