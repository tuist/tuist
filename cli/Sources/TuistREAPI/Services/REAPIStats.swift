import Foundation
import Synchronization

/// Per-run counters a `REAPICacheClient` writes into when a transfer gives up after retries,
/// so a caller can distinguish "fewer stalls" from "stalls turned into silent misses that
/// look like misses". A `nil` collector means the client runs without instrumentation.
///
/// This is a passive sink: the client increments; nothing is reported anywhere automatically.
/// A caller takes `snapshot` at the end of a run and renders it as a log line, metric or
/// server-side telemetry payload.
public final class REAPIStats: Sendable {
    private struct State {
        var findMissingFailures = 0
        var batchDownloadFailures = 0
        var batchDownloadDigestsLost = 0
        var batchUploadFailures = 0
        var batchUploadDigestsLost = 0
    }

    private let state = Mutex(State())

    public init() {}

    public struct Snapshot: Sendable, Equatable {
        /// How many `FindMissingBlobs` calls were swallowed after retries.
        public let findMissingFailures: Int
        /// How many `BatchReadBlobs` calls were swallowed after retries.
        public let batchDownloadFailures: Int
        /// How many digests were in those `BatchReadBlobs` batches and did not come back.
        /// A conservation check holds: `successful + batchDownloadDigestsLost + notFound ==
        /// requested`.
        public let batchDownloadDigestsLost: Int
        /// How many `BatchUpdateBlobs` calls were swallowed after retries.
        public let batchUploadFailures: Int
        /// How many digests were in those `BatchUpdateBlobs` batches and were not written.
        public let batchUploadDigestsLost: Int
    }

    public var snapshot: Snapshot {
        state.withLock { state in
            Snapshot(
                findMissingFailures: state.findMissingFailures,
                batchDownloadFailures: state.batchDownloadFailures,
                batchDownloadDigestsLost: state.batchDownloadDigestsLost,
                batchUploadFailures: state.batchUploadFailures,
                batchUploadDigestsLost: state.batchUploadDigestsLost
            )
        }
    }

    func recordFindMissingFailure() {
        state.withLock { $0.findMissingFailures += 1 }
    }

    func recordBatchDownloadFailure(digestsLost: Int) {
        state.withLock {
            $0.batchDownloadFailures += 1
            $0.batchDownloadDigestsLost += digestsLost
        }
    }

    func recordBatchUploadFailure(digestsLost: Int) {
        state.withLock {
            $0.batchUploadFailures += 1
            $0.batchUploadDigestsLost += digestsLost
        }
    }
}
