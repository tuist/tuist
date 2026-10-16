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
        var streamDownloadFailures = 0
        var streamDownloadDigestsLost = 0
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
        public let batchDownloadDigestsLost: Int
        /// How many streaming (`ByteStream.Read`) downloads of large blobs were swallowed
        /// after retries. A streaming failure costs exactly one digest, so
        /// `streamDownloadDigestsLost == streamDownloadFailures` by construction.
        public let streamDownloadFailures: Int
        /// How many digests were lost to streaming download failures. See
        /// `streamDownloadFailures` above; a conservation check holds across download paths:
        /// `successful + batchDownloadDigestsLost + streamDownloadDigestsLost + notFound ==
        /// requested`.
        public let streamDownloadDigestsLost: Int
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
                streamDownloadFailures: state.streamDownloadFailures,
                streamDownloadDigestsLost: state.streamDownloadDigestsLost,
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

    func recordStreamDownloadFailure(digestsLost: Int) {
        state.withLock {
            $0.streamDownloadFailures += 1
            $0.streamDownloadDigestsLost += digestsLost
        }
    }

    func recordBatchUploadFailure(digestsLost: Int) {
        state.withLock {
            $0.batchUploadFailures += 1
            $0.batchUploadDigestsLost += digestsLost
        }
    }
}
