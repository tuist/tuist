import Crypto
import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import Synchronization
import TuistEnvironment

public final class REAPICacheClient: REAPICacheStoring, Sendable { // swiftlint:disable:this type_body_length
    private let selector: LeastOutstandingSelector<GRPCClient<HTTP2ClientTransport.Posix>>
    private var clients: [GRPCClient<HTTP2ClientTransport.Posix>] { selector.clients }
    private let connections: [Task<Void, Error>]

    /// Reserves a client with the lowest in-flight count for the duration of
    /// `operation`. Replaces the previous round-robin picker so a connection whose
    /// peer has gone silent stops collecting new RPCs until it drains, and a connection
    /// that just failed with a transient/connection-shaped error gets a cooldown penalty
    /// so the next retry lands elsewhere. The lease is released in `defer` so throw and
    /// cancel paths release it too.
    private func withClient<T: Sendable>(
        _ operation: (GRPCClient<HTTP2ClientTransport.Posix>) async throws -> T
    ) async throws -> T {
        try await selector.withClient(shouldPenalize: Self.isConnectionFault, operation)
    }

    private let instanceName: String
    private let accountHandle: String
    private static let maximumBatchBytes: Int64 = 2 * 1024 * 1024
    private let negotiatedBatchBytes = Mutex<Int64>(maximumBatchBytes)
    private var batchBytes: Int64 { negotiatedBatchBytes.withLock { $0 } }
    private let compression = Mutex((stream: false, batchUpload: false))
    /// Whether the server splices blobs from chunks cut with the FastCDC parameters `REAPIChunking` uses.
    private let splicing = Mutex(false)
    /// Whether the server describes the chunks of a blob it stores as chunks through `SplitBlob`.
    private let splitting = Mutex(false)
    /// Large blobs upload as chunks that each fit in a batch, so splicing needs batches of the largest chunk.
    private var splicesBlobs: Bool {
        splicing.withLock { $0 } && batchBytes >= Int64(REAPIChunking.maximumChunkBytes)
    }

    private let fileSystem: FileSysteming
    private let token: @Sendable () async throws -> String
    private let guards: TransferGuards
    private let stats: REAPIStats?
    private let backpressureRetryPolicy: REAPIBackpressureRetryPolicy

    public init(
        endpoint: GRPCEndpoint,
        accountHandle: String,
        instanceName: String,
        fileSystem: FileSysteming = FileSystem(),
        guards: TransferGuards = .default,
        stats: REAPIStats? = nil,
        backpressureRetryPolicy: REAPIBackpressureRetryPolicy? = nil,
        environment: [String: String] = Environment.current.variables,
        token: @escaping @Sendable () async throws -> String
    ) async throws {
        var guards = guards
        if let raw = environment["TUIST_CACHE_CONCURRENCY_LIMIT"], let value = Int(raw), value > 0 {
            if guards.uploadConcurrency == nil { guards.uploadConcurrency = value }
            if guards.downloadConcurrency == nil { guards.downloadConcurrency = value }
        }
        if let value = guards.uploadConcurrency, value <= 0 {
            throw REAPICacheError.invalidTransferGuards(reason: "uploadConcurrency must be positive, got \(value)")
        }
        if let value = guards.downloadConcurrency, value <= 0 {
            throw REAPICacheError.invalidTransferGuards(reason: "downloadConcurrency must be positive, got \(value)")
        }
        var clients: [GRPCClient<HTTP2ClientTransport.Posix>] = []
        var connections: [Task<Void, Error>] = []
        do {
            for _ in 0 ..< 4 {
                let transport = try await REAPITransport.make(endpoint: endpoint, fileSystem: fileSystem)
                let client = GRPCClient(transport: transport)
                clients.append(client)
                connections.append(Task { try await client.runConnections() })
            }
        } catch {
            for client in clients {
                client.beginGracefulShutdown()
            }
            for connection in connections {
                connection.cancel()
            }
            throw error
        }
        selector = LeastOutstandingSelector(clients)
        self.connections = connections
        self.instanceName = instanceName
        self.accountHandle = accountHandle
        self.token = token
        self.fileSystem = fileSystem
        self.guards = guards
        self.stats = stats
        self.backpressureRetryPolicy = backpressureRetryPolicy ?? .init()
    }

    deinit {
        for client in clients {
            client.beginGracefulShutdown()
        }
        for connection in connections {
            connection.cancel()
        }
    }

    private func metadata() async throws -> Metadata {
        var result = Metadata()
        result.addString("Bearer \(try await token())", forKey: "authorization")
        result.addString(accountHandle, forKey: "x-tuist-account-handle")
        result.addString("module", forKey: "x-tuist-artifact-kind")
        return result
    }

    private var options: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(120)
        return options
    }

    /// What a transfer is held to while it runs.
    public struct TransferGuards: Sendable {
        /// How long a transfer may be idle on top of the time its largest message legitimately
        /// takes. A read then resumes from the byte it reached, so this is the guard a stalled
        /// transfer hits, not a wall-clock limit on a transfer that keeps receiving data.
        public var idleTimeout: Duration = .seconds(30)

        /// The slowest link a transfer is sized for, used for both call deadlines and for how
        /// long a message may legitimately take to arrive.
        public var slowestBytesPerSecond: Int64 = 4096

        /// The largest message a server is expected to send, which is what the idle guard waits
        /// for before the first message of a transfer arrives. Kura reads chunk at 512 KiB.
        public var largestExpectedMessageBytes: Int64 = 512 * 1024

        /// What a transfer is allowed on top of the time its bytes take at `slowestBytesPerSecond`,
        /// covering the round trip and the server's own work.
        public var baseAllowance: Duration = .seconds(120)

        /// What a batch call (`BatchReadBlobs`, `BatchUpdateBlobs`) is allowed on top of the time
        /// its bytes take at `batchSlowestBytesPerSecond`. Separate from `baseAllowance` because
        /// streaming reads need a much more generous bound to survive partial progress + resume,
        /// while a batch call either delivers in one shot or is better off failing fast and
        /// retrying on another connection.
        public var batchBaseAllowance: Duration = .seconds(30)

        /// The slowest link a batch call is sized for. 64 KiB/s gives a 2 MiB batch ~62 seconds
        /// before deadline, down from today's ~632 seconds. Tighter than streaming's 4 KiB/s floor
        /// on purpose: a batch slot wedged on a dead TCP connection ties up one of only 8-32 slots.
        public var batchSlowestBytesPerSecond: Int64 = 64 * 1024

        /// How many concurrent transfer tasks `downloadAvailableBlobs` runs. `nil` picks the
        /// built-in default: 8 when any blob is large enough to stream, 32 otherwise. A caller
        /// setting this must have validated the value is positive; invalid values are rejected at
        /// the config boundary, not silently clamped.
        public var downloadConcurrency: Int?

        /// Upload slots shared by batch and ByteStream tasks within an upload operation.
        /// Defaults to 8; explicit values override the environment configuration.
        public var uploadConcurrency: Int?

        public init() {}

        public static let `default` = TransferGuards()
    }

    /// How long `bytes` may take on the slowest link a transfer is sized for. It bounds a single
    /// call's deadline and, across attempts, how long resuming a blob may go on.
    private func allowance(forBytes bytes: Int64) -> Duration {
        guards.baseAllowance + .seconds(max(0, bytes) / guards.slowestBytesPerSecond)
    }

    /// How long a single batch call (`BatchReadBlobs`, `BatchUpdateBlobs`) may take. Tighter than
    /// `allowance(forBytes:)` so a stalled batch retries on another connection within ~2 minutes
    /// rather than ~10, now that `retryingDeadlineExceeded` is on for both batch RPCs.
    private func batchAllowance(forBytes bytes: Int64) -> Duration {
        guards.batchBaseAllowance + .seconds(max(0, bytes) / guards.batchSlowestBytesPerSecond)
    }

    /// Cap on consecutive read attempts that get no further into a blob. An attempt that reaches
    /// further resets it, so a download that keeps progressing keeps resuming.
    private static let maximumStalledReadAttempts = 3

    /// How much of a blob one upload message carries.
    private static let uploadChunkBytes = 1024 * 1024

    /// A deadline for a call carrying `bytes`, which a link at `slowestBytesPerSecond` meets.
    private func options(forBytes bytes: Int64) -> CallOptions {
        var options = options
        options.timeout = allowance(forBytes: bytes)
        return options
    }

    /// A tighter deadline for a batch call (`BatchReadBlobs`, `BatchUpdateBlobs`). The call is
    /// unary and can't resume, so a wedge is worth cutting fast and retrying on another connection.
    private func batchOptions(forBytes bytes: Int64) -> CallOptions {
        var options = options
        options.timeout = batchAllowance(forBytes: bytes)
        return options
    }

    /// Runs `operation`, failing it once nothing has been transferred for longer than a message
    /// may take. `heartbeat` reports the bytes of each message as it is sent or received, because
    /// a message only counts as activity once it is whole: a link at `slowestBytesPerSecond`
    /// needs `bytes / slowestBytesPerSecond` for one, and cutting sooner would abandon a transfer
    /// that is still being delivered.
    private func withIdleGuard<T: Sendable>(
        expectedMessageBytes: Int,
        _ operation: @escaping @Sendable (@escaping @Sendable (Int) -> Void) async throws -> T
    ) async throws -> T {
        let state = Mutex(IdleGuardState(largestMessageBytes: Int64(expectedMessageBytes)))
        let guards = guards
        return try await withThrowingTaskGroup(of: IdleGuardOutcome<T>.self) { group in
            group.addTask {
                .delivered(try await operation { bytes in
                    state.withLock {
                        $0.lastActivity = ContinuousClock.now
                        $0.largestMessageBytes = max($0.largestMessageBytes, Int64(bytes))
                    }
                })
            }
            group.addTask {
                while true {
                    let allowance = state.withLock {
                        guards.idleTimeout
                            + .seconds($0.largestMessageBytes / guards.slowestBytesPerSecond)
                            - (ContinuousClock.now - $0.lastActivity)
                    }
                    guard allowance > .zero else { return .idle }
                    try await Task.sleep(for: allowance)
                }
            }
            defer { group.cancelAll() }
            switch try await group.next() {
            case let .delivered(value): return value
            case .idle, nil: throw REAPICacheError.transferStalled
            }
        }
    }

    private struct IdleGuardState {
        var lastActivity = ContinuousClock.now
        var largestMessageBytes: Int64
    }

    private enum IdleGuardOutcome<T: Sendable>: Sendable {
        case delivered(T)
        case idle
    }

    /// Whether a failed transfer can be tried again. A refusal of the request itself, such as a
    /// missing blob or rejected credentials, is not retried; a transfer that broke or stalled is.
    private static func isResumable(_ error: any Error) -> Bool {
        if let error = error as? REAPICacheError { if case .transferStalled = error { return true }; return false }
        guard let error = error as? RPCError else { return false }
        return [.unavailable, .deadlineExceeded, .resourceExhausted, .aborted, .internalError, .unknown, .dataLoss]
            .contains(error.code)
    }

    /// Whether a failure is specifically about the current connection, as opposed to a request
    /// problem or server-side backpressure. Narrower than `isResumable`: a server-wide
    /// `.resourceExhausted` or a bad blob returning `.internalError` would otherwise cool a
    /// healthy client and attract retries onto the few remaining connections, which is both
    /// unfair and compounds the server-side pressure that caused the error.
    private static func isConnectionFault(_ error: any Error) -> Bool {
        guard let error = error as? RPCError else { return false }
        return [.unavailable, .deadlineExceeded].contains(error.code)
    }

    public func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult? {
        try REAPI.validate(digest)
        do {
            return try await retry {
                try await withClient { client in
                    try await Build_Bazel_Remote_Execution_V2_ActionCache.Client(wrapping: client).getActionResult(
                        .with {
                            $0.instanceName = instanceName
                            $0.actionDigest = digest
                            $0.digestFunction = .sha256
                        }, metadata: try await metadata(), options: options
                    )
                }
            }
        } catch let error as RPCError where error.code == .notFound {
            return nil
        }
    }

    public func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws {
        try REAPI.validate(digest)
        _ = try await retry(uploadBudget: .init(maximumDelay: backpressureRetryPolicy.maximumCumulativeDelay)) {
            try await withClient { client in
                try await Build_Bazel_Remote_Execution_V2_ActionCache.Client(wrapping: client).updateActionResult(
                    .with {
                        $0.instanceName = instanceName
                        $0.actionDigest = digest
                        $0.actionResult = result
                        $0.digestFunction = .sha256
                    }, metadata: try await metadata(), options: options
                )
            }
        }
    }

    /// The message a cache node refused the account with for billing reasons, such as an exhausted free tier or
    /// a failed subscription payment. gRPC has no status for payment required, so the node marks the permission
    /// denial with a `tuist-refusal-reason` metadata entry. `nil` for every other error.
    public static func billingRefusalMessage(of error: Error) -> String? {
        guard let error = error as? RPCError, error.code == .permissionDenied,
              error.metadata[stringValues: "tuist-refusal-reason"].contains(where: { $0 == "payment_required" }),
              !error.message.isEmpty
        else { return nil }
        return error.message
    }

    public func validateCapabilities() async throws {
        var options = options
        options.timeout = .seconds(10)
        let response = try await withClient { client in
            try await Build_Bazel_Remote_Execution_V2_Capabilities.Client(wrapping: client).getCapabilities(
                .with { $0.instanceName = instanceName }, metadata: try await metadata(), options: options
            )
        }
        guard response.hasCacheCapabilities, response.cacheCapabilities.digestFunctions.contains(.sha256) else {
            throw REAPICacheError.unsupportedEndpoint
        }
        compression.withLock {
            $0 = (
                response.cacheCapabilities.supportedCompressors.contains(.zstd),
                response.cacheCapabilities.supportedBatchUpdateCompressors.contains(.zstd)
            )
        }
        let advertised = response.cacheCapabilities.maxBatchTotalSizeBytes
        if advertised > 0 { negotiatedBatchBytes.withLock { $0 = min(advertised, Self.maximumBatchBytes) } }
        let chunking = response.cacheCapabilities.fastCdc2020Params
        splicing.withLock {
            $0 = response.cacheCapabilities.spliceBlobSupport && response.cacheCapabilities.hasFastCdc2020Params
                && chunking.avgChunkSizeBytes == UInt64(REAPIChunking.averageChunkBytes) && chunking.seed == 0
        }
        splitting.withLock { $0 = response.cacheCapabilities.splitBlobSupport }
    }

    /// Streaming reads resume from the byte they reached, so a deadline-exceeded attempt that
    /// already covered a slow link's share of the payload is not worth repeating twice more; its
    /// caller passes `retryingDeadlineExceeded: false`. Batch calls use the shorter `batchAllowance`
    /// (around 62 seconds for a 2 MiB payload) so retrying on deadline is cheap and lets the next
    /// attempt land on a different connection via `LeastOutstandingSelector`. Deadline retries are
    /// bounded to two total attempts so a server that is slow for its own reasons does not get
    /// three times the load from each client.
    private func retry<T>(
        retryingDeadlineExceeded: Bool = true,
        uploadBudget: REAPIUploadRetryBudget? = nil,
        _ operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var deadlineAttempts = 0
        var backpressureAttempts = 0
        var backpressureDelay: Duration = .zero
        while true {
            do { return try await operation() } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                if let uploadBudget, let rpcError = error as? RPCError, rpcError.code == .resourceExhausted {
                    guard backpressureAttempts < backpressureRetryPolicy.maximumRetryCount else { throw error }
                    let delay = backpressureRetryPolicy.delay(for: backpressureAttempts, error: rpcError)
                    guard uploadBudget.consume(delay) else {
                        throw RPCError(
                            code: .resourceExhausted,
                            message: "\(rpcError.message) (upload admission retry wait budget exhausted)",
                            metadata: rpcError.metadata,
                            cause: rpcError
                        )
                    }
                    try await Task.sleep(for: delay)
                    backpressureAttempts += 1
                    continue
                }
                if (error as? RPCError)?.code == .deadlineExceeded {
                    if !retryingDeadlineExceeded { throw error }
                    deadlineAttempts += 1
                    if deadlineAttempts >= 2 { throw error }
                }
                guard attempt < 2, Self.isRetryable(error) else { throw error }
                var delay: Duration = .milliseconds((1 << attempt) * 200 + Int.random(in: 0 ... 100))
                if let rpcError = error as? RPCError, rpcError.code == .resourceExhausted {
                    if let hinted = REAPIBackpressureRetryPolicy.retryInfoDelay(rpcError) {
                        delay = max(delay, hinted)
                    }
                    guard delay <= .seconds(1) - backpressureDelay else { throw error }
                    backpressureDelay += delay
                }
                try await Task.sleep(for: delay)
                attempt += 1
            }
        }
    }

    /// A transfer that stalled is tried again like a transient server failure: a write carries the
    /// blob from its first byte, so the attempt it replaces delivered nothing that can be kept.
    private static func isRetryable(_ error: any Error) -> Bool {
        if let error = error as? REAPICacheError { if case .transferStalled = error { return true }; return false }
        guard let error = error as? RPCError else { return false }
        return [.unavailable, .resourceExhausted, .deadlineExceeded].contains(error.code)
    }

    private static func batchFailure(codes: [Int32]) -> RPCError? {
        let code: RPCError.Code
        if codes.contains(8) {
            code = .resourceExhausted
        } else if codes.contains(4) {
            code = .deadlineExceeded
        } else if codes.contains(14) {
            code = .unavailable
        } else {
            return nil
        }
        return RPCError(code: code, message: "Cache batch temporarily rejected")
    }

    private func batches(_ digests: [REAPI.Digest]) -> [[REAPI.Digest]] {
        var result: [[REAPI.Digest]] = []
        var batch: [REAPI.Digest] = []
        var bytes: Int64 = 0
        for digest in digests {
            if !batch.isEmpty, bytes + digest.sizeBytes > batchBytes || batch.count == 128 {
                result.append(batch); batch = []; bytes = 0
            }
            batch.append(digest); bytes += digest.sizeBytes
        }
        if !batch.isEmpty { result.append(batch) }
        return result
    }

    public func uploadBlobs(_ blobs: [REAPI.Digest: URL]) async throws {
        let upload = try await uploadAvailableBlobs(blobs)
        guard upload.available.count == blobs.count else {
            throw REAPICacheError.uploadFailed(reason: upload.failures.values.sorted().first ?? "no reason was reported")
        }
    }

    public func uploadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> REAPIBlobUpload {
        for digest in blobs.keys {
            try REAPI.validate(digest)
        }
        let operation = UploadOperation(
            budget: REAPIUploadRetryBudget(maximumDelay: backpressureRetryPolicy.maximumCumulativeDelay),
            concurrency: guards.uploadConcurrency ?? 8
        )
        let (missing, existing) = try await findMissing(Array(blobs.keys), in: operation) { batch, reason in
            operation.fail(batch, reason: reason)
            self.stats?.recordFindMissingFailure()
        }
        let recipes = try await recipes(for: missing.filter { $0.sizeBytes > batchBytes }, in: blobs, operation: operation)
        var sources = blobs.mapValues { BlobSource(url: $0) }
        for (digest, chunks) in recipes {
            for chunk in chunks where sources[chunk.digest] == nil {
                sources[chunk.digest] = BlobSource(
                    url: blobs[digest]!,
                    range: chunk.offset ..< chunk.offset + chunk.digest.sizeBytes
                )
            }
        }
        // A chunk whose presence query failed is uploaded anyway: sending it again costs bytes, not correctness.
        let unknownChunks = Mutex<Set<REAPI.Digest>>([])
        let chunkDigests = Set(recipes.values.flatMap { $0.map(\.digest) })
        let (missingChunks, _) = try await findMissing(Array(chunkDigests), in: operation) { batch, _ in
            unknownChunks.withLock { $0.formUnion(batch) }
        }
        let chunks = missingChunks.union(unknownChunks.withLock { $0 })
        // The largest blobs go first so their chunks, and the splices waiting on them, do not trail the operation.
        var order: [REAPI.Digest] = []
        var queued = Set<REAPI.Digest>()
        for (_, recipe) in recipes.sorted(by: { $0.key.sizeBytes > $1.key.sizeBytes }) {
            for chunk in recipe where chunks.contains(chunk.digest) && queued.insert(chunk.digest).inserted {
                order.append(chunk.digest)
            }
        }
        order.append(contentsOf: missing.filter { recipes[$0] == nil && operation.failure(of: $0) == nil })
        let (uploaded, spliced) = try await uploadAndSplice(order, recipes: recipes, from: sources, in: operation)
        let available = existing.union(uploaded).union(spliced).filter { blobs[$0] != nil }
        return REAPIBlobUpload(
            available: available,
            failures: operation.failures.filter { blobs[$0.key] != nil && !available.contains($0.key) }
        )
    }

    /// What one `uploadAvailableBlobs` call shares across its phases.
    private final class UploadOperation: Sendable {
        let budget: REAPIUploadRetryBudget
        let concurrency: Int
        private let reasons = Mutex<[REAPI.Digest: String]>([:])

        init(budget: REAPIUploadRetryBudget, concurrency: Int) {
            self.budget = budget
            self.concurrency = concurrency
        }

        var failures: [REAPI.Digest: String] { reasons.withLock { $0 } }

        func failure(of digest: REAPI.Digest) -> String? { reasons.withLock { $0[digest] } }

        func fail(_ digests: some Sequence<REAPI.Digest>, reason: String) {
            reasons.withLock { for digest in digests {
                $0[digest] = reason
            } }
        }
    }

    /// The bytes of a blob: a whole file, or the range of one that holds a chunk.
    private struct BlobSource: Sendable {
        let url: URL
        var range: Range<Int64>?
    }

    private func read(_ source: BlobSource) async throws -> Data {
        guard let range = source.range else {
            return try await fileSystem.readFile(at: AbsolutePath(validating: source.url.path))
        }
        // FileSystem has no ranged reads.
        let handle = try FileHandle(forReadingFrom: source.url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let data = try handle.read(upToCount: range.count) ?? Data()
        guard data.count == range.count else { throw REAPICacheError.corruptBlob }
        return data
    }

    /// Which of `digests` the cache lacks and which it holds. Digests whose query failed are in neither set and
    /// are reported to `onFailure`.
    private func findMissing(
        _ digests: [REAPI.Digest],
        in operation: UploadOperation,
        onFailure: @escaping @Sendable ([REAPI.Digest], String) -> Void
    ) async throws -> (missing: Set<REAPI.Digest>, present: Set<REAPI.Digest>) {
        // Missing-blob requests contain only digests, so batch by metadata count, not file size.
        let queries = stride(from: 0, to: digests.count, by: 1024).map {
            Array(digests[$0 ..< min($0 + 1024, digests.count)])
        }
        let missing = Mutex<Set<REAPI.Digest>>([])
        let present = try await transfer(queries, maxConcurrentTasks: operation.concurrency) { batch in
            do {
                let response = try await self.retry(uploadBudget: operation.budget) {
                    try await self.withClient { client in
                        try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.Client(wrapping: client)
                            .findMissingBlobs(.with {
                                $0.instanceName = self.instanceName; $0.blobDigests = batch; $0.digestFunction = .sha256
                            }, metadata: try await self.metadata(), options: self.options)
                    }
                }
                let absent = Set(response.missingBlobDigests)
                guard absent.isSubset(of: Set(batch)) else { throw REAPICacheError.invalidDigest }
                missing.withLock { $0.formUnion(absent) }
                return Set(batch).subtracting(absent)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                onFailure(batch, REAPICall.findMissingBlobs.describeFailure(error))
                return []
            }
        }
        return (missing.withLock { $0 }, present)
    }

    /// Cuts each blob a ByteStream write would otherwise carry into chunks that each fit in a batch, so no upload
    /// request takes longer than a batch however slow the link is. Proxies such as CDNs end a request whose response
    /// has not started within a fixed time, and a ByteStream write is only answered once its last byte arrives.
    /// Empty when the server does not splice blobs.
    private func recipes(
        for digests: Set<REAPI.Digest>,
        in blobs: [REAPI.Digest: URL],
        operation: UploadOperation
    ) async throws -> [REAPI.Digest: [REAPIChunking.Chunk]] {
        guard splicesBlobs, !digests.isEmpty else { return [:] }
        let recipes = Mutex<[REAPI.Digest: [REAPIChunking.Chunk]]>([:])
        _ = try await transfer(digests.map { [$0] }, maxConcurrentTasks: operation.concurrency) { batch in
            let digest = batch[0]
            do {
                let chunks = try REAPIChunking.chunks(of: blobs[digest]!, digest: digest)
                if chunks.count <= REAPIChunking.maximumChunks { recipes.withLock { $0[digest] = chunks } }
            } catch {
                operation.fail([digest], reason: "The blob could not be read for a chunked upload: \(REAPI.describe(error))")
            }
            return []
        }
        return recipes.withLock { $0 }
    }

    private enum SpliceOutcome: Sendable {
        case spliced, unsupported, evicted, failed
    }

    /// Splices one blob. A chunk the cache reported present can be evicted before the splice reads it; when
    /// `evictionIsRetried`, that is reported for the caller to repair instead of as a failure.
    private func spliceOnce(
        _ digest: REAPI.Digest,
        chunks: [REAPIChunking.Chunk],
        evictionIsRetried: Bool,
        in operation: UploadOperation
    ) async throws -> SpliceOutcome {
        do {
            try await spliceBlob(digest, chunks: chunks, budget: operation.budget)
            return .spliced
        } catch let error as RPCError where error.code == .unimplemented {
            splicing.withLock { $0 = false }
            return .unsupported
        } catch let error as RPCError where evictionIsRetried && [.notFound, .failedPrecondition].contains(error.code) {
            return .evicted
        } catch {
            if error is CancellationError || Task.isCancelled { throw error }
            operation.fail([digest], reason: REAPICall.spliceBlob.describeFailure(error))
            return .failed
        }
    }

    private enum UploadResult: Sendable {
        case batch(Set<REAPI.Digest>)
        case splice(REAPI.Digest, SpliceOutcome)
    }

    /// Uploads `digests` in batches and splices each recipe as soon as its last missing chunk lands, so the cache
    /// verifying a splice, which reads the blob back, overlaps the uploads still in flight. Ready splices go ahead of
    /// queued batches within the same concurrency. A splice that finds chunks evicted uploads them again and is
    /// retried once, and a server that does not implement splicing gets those blobs whole.
    private func uploadAndSplice(
        _ digests: [REAPI.Digest],
        recipes: [REAPI.Digest: [REAPIChunking.Chunk]],
        from sources: [REAPI.Digest: BlobSource],
        in operation: UploadOperation
    ) async throws -> (uploaded: Set<REAPI.Digest>, spliced: Set<REAPI.Digest>) {
        let uploading = Set(digests)
        var pending: [REAPI.Digest: Set<REAPI.Digest>] = [:]
        var blobsByChunk: [REAPI.Digest: [REAPI.Digest]] = [:]
        var ready: [REAPI.Digest] = []
        for (blob, recipe) in recipes {
            let missing = Set(recipe.map(\.digest)).intersection(uploading)
            if missing.isEmpty { ready.append(blob) } else { pending[blob] = missing }
            for chunk in missing {
                blobsByChunk[chunk, default: []].append(blob)
            }
        }
        var queue = batches(digests)[...]
        var uploaded = Set<REAPI.Digest>()
        var spliced = Set<REAPI.Digest>()
        var evicted: [REAPI.Digest: [REAPIChunking.Chunk]] = [:]
        var unsupported = Set<REAPI.Digest>()
        try await withThrowingTaskGroup(of: UploadResult.self) { group in
            var running = 0
            while true {
                while running < operation.concurrency {
                    if let blob = ready.popLast() {
                        let recipe = recipes[blob]!
                        group.addTask {
                            try await .splice(blob, self.spliceOnce(blob, chunks: recipe, evictionIsRetried: true, in: operation))
                        }
                    } else if let batch = queue.popFirst() {
                        group.addTask { try await .batch(self.uploadBatch(batch, from: sources, in: operation)) }
                    } else {
                        break
                    }
                    running += 1
                }
                guard let result = try await group.next() else { break }
                running -= 1
                switch result {
                case let .batch(successful):
                    uploaded.formUnion(successful)
                    for chunk in successful {
                        for blob in blobsByChunk[chunk] ?? [] {
                            pending[blob]?.remove(chunk)
                            if pending[blob]?.isEmpty == true {
                                pending[blob] = nil
                                ready.append(blob)
                            }
                        }
                    }
                case let .splice(blob, .spliced): spliced.insert(blob)
                case let .splice(blob, .unsupported): unsupported.insert(blob)
                case let .splice(blob, .evicted): evicted[blob] = recipes[blob]
                case .splice(_, .failed): break
                }
            }
        }
        for (blob, missing) in pending {
            operation.fail(
                [blob],
                reason: missing.lazy.compactMap { operation.failure(of: $0) }.first
                    ?? "A chunk of the blob was not uploaded"
            )
        }
        if !evicted.isEmpty {
            let repairs = evicted
            let unknown = Mutex<Set<REAPI.Digest>>([])
            let (missing, _) = try await findMissing(
                Array(Set(repairs.values.flatMap { $0.map(\.digest) })), in: operation
            ) { batch, _ in unknown.withLock { $0.formUnion(batch) } }
            _ = try await upload(missing.union(unknown.withLock { $0 }), from: sources, in: operation)
            let unserved = Mutex<Set<REAPI.Digest>>([])
            try await spliced.formUnion(transfer(repairs.keys.map { [$0] }, maxConcurrentTasks: operation.concurrency) { batch in
                switch try await self.spliceOnce(batch[0], chunks: repairs[batch[0]]!, evictionIsRetried: false, in: operation) {
                case .spliced: return [batch[0]]
                case .unsupported: unserved.withLock { _ = $0.insert(batch[0]) }
                case .evicted, .failed: break
                }
                return []
            })
            unsupported.formUnion(unserved.withLock { $0 })
        }
        if !unsupported.isEmpty {
            try await spliced.formUnion(upload(unsupported, from: sources, in: operation))
        }
        return (uploaded, spliced)
    }

    private func spliceBlob(
        _ digest: REAPI.Digest,
        chunks: [REAPIChunking.Chunk],
        budget: REAPIUploadRetryBudget
    ) async throws {
        let response = try await retry(uploadBudget: budget) {
            try await withClient { client in
                try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.Client(wrapping: client).spliceBlob(
                    .with {
                        $0.instanceName = instanceName
                        $0.blobDigest = digest
                        $0.chunkDigests = chunks.map(\.digest)
                        $0.digestFunction = .sha256
                        $0.chunkingFunction = .fastCdc2020
                    }, metadata: try await metadata(), options: options
                )
            }
        }
        guard response.blobDigest == digest else { throw REAPICacheError.invalidDigest }
    }

    /// Uploads blobs in batches, and a blob too large for a batch as a ByteStream write. Returns the blobs the cache
    /// accepted, recording why each other one was not.
    private func upload(
        _ digests: Set<REAPI.Digest>,
        from sources: [REAPI.Digest: BlobSource],
        in operation: UploadOperation
    ) async throws -> Set<REAPI.Digest> {
        try await transfer(batches(Array(digests)), maxConcurrentTasks: operation.concurrency) { batch in
            try await self.uploadBatch(batch, from: sources, in: operation)
        }
    }

    /// Uploads one batch, or one blob too large for a batch as a ByteStream write.
    private func uploadBatch(
        _ batch: [REAPI.Digest],
        from sources: [REAPI.Digest: BlobSource],
        in operation: UploadOperation
    ) async throws -> Set<REAPI.Digest> {
        var successful = Set<REAPI.Digest>()
        if batch.count == 1, let digest = batch.first, digest.sizeBytes > self.batchBytes {
            do {
                try await retry(uploadBudget: operation.budget) {
                    try await self.uploadBlob(digest, from: sources[digest]!.url)
                }
                successful.insert(digest)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                operation.fail([digest], reason: REAPICall.byteStreamWrite.describeFailure(error))
            }
        } else {
            var rejections: [REAPI.Digest: String] = [:]
            var batchFailure: String?
            do {
                try await retry(uploadBudget: operation.budget) {
                    rejections = [:]
                    let pending = Set(batch).subtracting(successful)
                    var requests: [Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsRequest.Request] = []
                    for digest in pending {
                        let data = try await self.read(sources[digest]!)
                        let compressed = self.compression.withLock { $0.batchUpload } && data.count >= REAPICompression
                            .threshold
                            ? try REAPICompression.compress(data) : data
                        requests.append(.with {
                            $0.digest = digest
                            $0.data = compressed.count < data.count ? compressed : data
                            $0.compressor = compressed.count < data.count ? .zstd : .identity
                        })
                    }
                    let bytes = requests.reduce(0) { $0 + Int64($1.data.count) }
                    // Chunks carry what a ByteStream write used to, so they keep its allowance for a slow link.
                    let carriesChunks = pending.contains { sources[$0]!.range != nil }
                    let result = try await self.withClient { client in
                        try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage
                            .Client(wrapping: client)
                            .batchUpdateBlobs(
                                .with {
                                    $0.instanceName = self.instanceName; $0.digestFunction = .sha256
                                    $0.requests = requests
                                },
                                metadata: try await self.metadata(),
                                options: carriesChunks ? self.options(forBytes: bytes) : self.batchOptions(forBytes: bytes)
                            )
                    }
                    successful
                        .formUnion(result.responses.filter { $0.status.code == 0 && pending.contains($0.digest) }
                            .map(\.digest))
                    for response in result.responses where response.status.code != 0 && pending.contains(response.digest) {
                        rejections[response.digest] = "\(REAPICall.batchUpdateBlobs.rawValue) rejected the blob "
                            + "with status \(response.status.code): \(response.status.message)"
                    }
                    if let error = Self.batchFailure(codes: result.responses.map(\.status.code)) {
                        throw error
                    }
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                batchFailure = REAPICall.batchUpdateBlobs.describeFailure(error)
            }
            let rejected = Set(batch).subtracting(successful)
            if batchFailure != nil, !rejected.isEmpty {
                stats?.recordBatchUploadFailure(digestsLost: rejected.count)
            }
            for digest in rejected {
                operation.fail(
                    [digest],
                    reason: rejections[digest] ?? batchFailure
                        ?? "\(REAPICall.batchUpdateBlobs.rawValue) returned no status for the blob"
                )
            }
        }
        return successful
    }

    public func downloadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest> {
        try await downloadAvailableBlobs(blobs, onDownloaded: { _ in })
    }

    public func downloadAvailableBlobs(
        _ blobs: [REAPI.Digest: URL],
        orderedDigests: [REAPI.Digest] = [],
        onDownloaded: @escaping @Sendable (REAPI.Digest) async throws -> Void
    ) async throws -> Set<REAPI.Digest> {
        for digest in blobs.keys {
            try REAPI.validate(digest)
        }
        var synthesized = Set<REAPI.Digest>()
        if let path = blobs[REAPI.emptyBlob] {
            do {
                try Data().write(to: path)
                try await onDownloaded(REAPI.emptyBlob)
                synthesized.insert(REAPI.emptyBlob)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
            }
        }
        var seen: Set<REAPI.Digest> = [REAPI.emptyBlob]
        var ordered = orderedDigests.filter { blobs[$0] != nil && seen.insert($0).inserted }
        ordered.append(contentsOf: blobs.keys.filter { !seen.contains($0) })
        let usesStreams = blobs.keys.contains { $0.sizeBytes > batchBytes }
        let maxConcurrentTasks = guards.downloadConcurrency ?? (usesStreams ? 8 : 32)
        let chunkReads = Permits(maxConcurrentTasks)
        return try await synthesized.union(transfer(batches(ordered), maxConcurrentTasks: maxConcurrentTasks) { batch in
            if batch.count == 1, let digest = batch.first, digest.sizeBytes > self.batchBytes {
                // `downloadBlob` resumes from the byte it reached, which subsumes a restart from zero.
                do {
                    if try await !self.downloadSplitBlob(digest, to: blobs[digest]!, permits: chunkReads) {
                        try await self.downloadBlob(digest, to: blobs[digest]!)
                    }
                } catch let error as RPCError where error.code == .notFound {
                    // A legitimate server-reported miss, equivalent to a `NOT_FOUND` status in
                    // the batch response. Not a network loss; do not count it in stats so the
                    // conservation across paths holds.
                    return []
                } catch {
                    if error is CancellationError || Task.isCancelled { throw error }
                    self.stats?.recordStreamDownloadFailure(digestsLost: 1)
                    return []
                }
                // `onDownloaded` lives outside the counted block: a local-admission failure here
                // is a caller-side problem, matching the batch path, which silently drops the
                // digest without recording it as a network loss either.
                do {
                    try await onDownloaded(digest)
                } catch {
                    if error is CancellationError || Task.isCancelled { throw error }
                    return []
                }
                return [digest]
            }
            var successful = Set<REAPI.Digest>()
            do {
                try await self.retry {
                    let pending = batch.filter { !successful.contains($0) }
                    let response = try await self.withClient { client in
                        try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage
                            .Client(wrapping: client)
                            .batchReadBlobs(
                                .with {
                                    $0.instanceName = self.instanceName
                                    $0.digests = pending
                                    $0.acceptableCompressors = [.zstd]
                                    $0.digestFunction = .sha256
                                },
                                metadata: try await self.metadata(),
                                options: self.batchOptions(forBytes: pending.reduce(0) { $0 + $1.sizeBytes })
                            )
                    }
                    for output in response.responses where output.status.code == 0 {
                        guard batch.contains(output.digest), !successful.contains(output.digest),
                              let path = blobs[output.digest] else { continue }
                        do {
                            let data: Data
                            switch output.compressor {
                            case .identity: data = output.data
                            case .zstd: data = try REAPICompression.decompress(output.data, size: output.digest.sizeBytes)
                            default: continue
                            }
                            guard REAPI.digest(data) == output.digest else { continue }
                            // These are private download files; the caller publishes verified content atomically.
                            try Data().write(to: path)
                            let handle = try FileHandle(forWritingTo: path)
                            do {
                                try handle.write(contentsOf: data)
                                try handle.close()
                            } catch {
                                try? handle.close()
                                throw error
                            }
                            try await onDownloaded(output.digest)
                            successful.insert(output.digest)
                        } catch {
                            if error is CancellationError || Task.isCancelled { throw error }
                        }
                    }
                    if let error = Self.batchFailure(codes: response.responses.map(\.status.code)) {
                        throw error
                    }
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                let lost = Set(batch).subtracting(successful).count
                if lost > 0 { self.stats?.recordBatchDownloadFailure(digestsLost: lost) }
            }
            return successful
        })
    }

    private func transfer(
        _ batches: [[REAPI.Digest]],
        maxConcurrentTasks: Int = 8,
        operation: @escaping @Sendable ([REAPI.Digest]) async throws -> Set<REAPI.Digest>
    ) async throws -> Set<REAPI.Digest> {
        var successful = Set<REAPI.Digest>()
        try await withThrowingTaskGroup(of: Set<REAPI.Digest>.self) { group in
            var pending = batches.makeIterator()
            func enqueue(_ batch: [REAPI.Digest]) {
                group.addTask {
                    do { return try await operation(batch) } catch {
                        if error is CancellationError || Task.isCancelled { throw error }
                        return []
                    }
                }
            }
            for _ in 0 ..< maxConcurrentTasks {
                if let batch = pending.next() { enqueue(batch) }
            }
            while let completed = try await group.next() {
                successful.formUnion(completed)
                if let batch = pending.next() { enqueue(batch) }
            }
        }
        return successful
    }

    private func streamOptions(_ digest: REAPI.Digest, from offset: Int64 = 0) -> CallOptions {
        options(forBytes: digest.sizeBytes - offset)
    }

    private func uploadBlob(_ digest: REAPI.Digest, from path: URL) async throws {
        let compressed = compression.withLock { $0.stream } && digest.sizeBytes >= REAPICompression.threshold
        let encoding = compressed ? "compressed-blobs/zstd" : "blobs"
        let resource = "\(instanceName)/uploads/\(UUID().uuidString)/\(encoding)/\(digest.hash)/\(digest.sizeBytes)"
        let sentBytes = Mutex<Int64>(0)
        // A write cannot resume: a stream carries the blob from its first byte, and the committed
        // size of an unfinished upload is not reported, so a broken attempt starts over.
        let committedSize = try await withIdleGuard(expectedMessageBytes: Self.uploadChunkBytes) { heartbeat in
            let request = StreamingClientRequest<Google_Bytestream_WriteRequest>(
                metadata: try await self.metadata()
            ) { writer in
                let handle = try FileHandle(forReadingFrom: path)
                defer { try? handle.close() }
                let encoder = compressed ? try REAPICompression.Encoder() : nil
                var offset: Int64 = 0
                var consumed: Int64 = 0
                repeat {
                    let input = try handle.read(upToCount: Self.uploadChunkBytes) ?? Data()
                    consumed += Int64(input.count)
                    guard consumed <= digest.sizeBytes, !input.isEmpty || consumed == digest.sizeBytes else {
                        throw REAPICacheError.corruptBlob
                    }
                    let finished = consumed == digest.sizeBytes
                    let data = try encoder?.encode(input, finish: finished) ?? input
                    // A zstd frame can buffer an input chunk without emitting any bytes yet.
                    if !data.isEmpty || finished {
                        try await writer.write(.with {
                            $0.resourceName = resource
                            $0.writeOffset = offset
                            $0.data = data
                            $0.finishWrite = finished
                        })
                        offset += Int64(data.count)
                        sentBytes.withLock { $0 = offset }
                        heartbeat(data.count)
                    }
                } while consumed < digest.sizeBytes
            }
            return try await self.withClient { client in
                try await Google_Bytestream_ByteStream.Client(wrapping: client)
                    .write(request: request, options: self.streamOptions(digest)).committedSize
            }
        }
        // REAPI permits -1 when a concurrent compressed upload has already completed.
        guard committedSize == (compressed ? sentBytes.withLock { $0 } : digest.sizeBytes)
            || (compressed && committedSize == -1) else { throw REAPICacheError.corruptBlob }
    }

    /// Reads a blob the cache stores as chunks by fetching its chunks in compressed batches. A cache may not serve a
    /// chunked blob through a compressed ByteStream read, and batches keep every request short. Returns `false`,
    /// leaving the read to ByteStream, when the cache holds the blob whole or describes chunks this client cannot
    /// batch.
    private func downloadSplitBlob(_ digest: REAPI.Digest, to path: URL, permits: Permits) async throws -> Bool {
        guard splitting.withLock({ $0 }) else { return false }
        let recipe: [REAPI.Digest]
        do {
            recipe = try await retry {
                try await withClient { client in
                    try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.Client(wrapping: client).splitBlob(
                        .with {
                            $0.instanceName = instanceName
                            $0.blobDigest = digest
                            $0.digestFunction = .sha256
                            $0.chunkingFunction = .fastCdc2020
                        }, metadata: try await metadata(), options: options
                    )
                }
            }.chunkDigests
        } catch let error as RPCError where error.code == .notFound {
            return false
        } catch let error as RPCError where error.code == .unimplemented {
            splitting.withLock { $0 = false }
            return false
        }
        guard !recipe.isEmpty, recipe.count <= REAPIChunking.maximumChunks,
              recipe.allSatisfy({ (try? REAPI.validate($0)) != nil && $0.sizeBytes > 0 && $0.sizeBytes <= batchBytes }),
              recipe.reduce(0, { $0 + $1.sizeBytes }) == digest.sizeBytes
        else { return false }
        var offsets: [REAPI.Digest: [Int64]] = [:]
        var unique: [REAPI.Digest] = []
        var offset: Int64 = 0
        for chunk in recipe {
            if offsets[chunk] == nil { unique.append(chunk) }
            offsets[chunk, default: []].append(offset)
            offset += chunk.sizeBytes
        }
        let chunkOffsets = offsets
        do {
            try Data().write(to: path)
            let failure = Mutex<(any Error)?>(nil)
            // The large blobs of a download share its read permits, so a blob uses the slots others are done with
            // while the batches in flight never exceed the download's transfer limit.
            let written = try await withThrowingTaskGroup(of: Int.self) { group in
                for batch in batches(unique) {
                    group.addTask {
                        await permits.acquire()
                        defer { permits.release() }
                        do {
                            let chunks = try await self.readChunks(batch)
                            let handle = try FileHandle(forWritingTo: path)
                            defer { try? handle.close() }
                            for (chunk, data) in chunks {
                                for offset in chunkOffsets[chunk]! {
                                    try handle.seek(toOffset: UInt64(offset))
                                    try handle.write(contentsOf: data)
                                }
                            }
                            return chunks.count
                        } catch {
                            if error is CancellationError || Task.isCancelled { throw error }
                            failure.withLock { $0 = $0 ?? error }
                            return 0
                        }
                    }
                }
                return try await group.reduce(0, +)
            }
            guard written == unique.count else {
                throw failure.withLock { $0 } ?? REAPICacheError.corruptBlob
            }
            guard try REAPI.digest(file: path) == digest else { throw REAPICacheError.corruptBlob }
            return true
        } catch {
            try? await fileSystem.remove(AbsolutePath(validating: path.path))
            throw error
        }
    }

    /// Reads every chunk in `digests` through batch reads, verifying each against its digest. The deadline is the
    /// allowance of the ByteStream read the chunks replace, not the tighter one of a batch of small blobs.
    private func readChunks(_ digests: [REAPI.Digest]) async throws -> [REAPI.Digest: Data] {
        var chunks: [REAPI.Digest: Data] = [:]
        try await retry {
            let pending = digests.filter { chunks[$0] == nil }
            let response = try await withClient { client in
                try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.Client(wrapping: client).batchReadBlobs(
                    .with {
                        $0.instanceName = instanceName
                        $0.digests = pending
                        $0.acceptableCompressors = [.zstd]
                        $0.digestFunction = .sha256
                    },
                    metadata: try await metadata(),
                    options: options(forBytes: pending.reduce(0) { $0 + $1.sizeBytes })
                )
            }
            for output in response.responses where output.status.code == 0 && pending.contains(output.digest) {
                let data: Data
                switch output.compressor {
                case .identity: data = output.data
                case .zstd: data = try REAPICompression.decompress(output.data, size: output.digest.sizeBytes)
                default: continue
                }
                if REAPI.digest(data) == output.digest { chunks[output.digest] = data }
            }
            if let error = Self.batchFailure(codes: response.responses.map(\.status.code)) { throw error }
        }
        guard chunks.count == digests.count else {
            throw RPCError(code: .notFound, message: "The cache is missing chunks of the blob")
        }
        return chunks
    }

    /// Reads a blob, resuming from the byte it reached when a read breaks partway. The bytes and the
    /// hash of everything received so far carry across attempts, so a broken transfer costs the rest
    /// of the blob rather than all of it.
    public func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        try REAPI.validate(digest)
        // Streaming owns this temporary file; syncing an empty file before filling it adds no durability.
        try Data().write(to: path)
        if digest == REAPI.emptyBlob { return }
        do {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            let progress = ReadProgress()
            let startedReading = ContinuousClock.now
            var stalledAttempts = 0
            var backpressureDelay: Duration = .zero
            var failure: (any Error)?
            var compressed = compression.withLock { $0.stream } && digest.sizeBytes >= REAPICompression.threshold
            while true {
                let before = progress.received
                do {
                    try await readAttempt(digest, from: before, compressed: compressed, into: handle, progress: progress)
                    failure = nil
                } catch let error as RPCError where compressed && error.code == .unimplemented {
                    // A cache that stores the blob as chunks may not serve it compressed.
                    compressed = false
                    continue
                } catch {
                    if error is CancellationError || Task.isCancelled { throw error }
                    guard Self.isResumable(error) else { throw error }
                    failure = error
                }
                let received = progress.received
                if received == digest.sizeBytes { break }
                // Resuming is bounded by the bytes it has to show for itself: a download may take as
                // long as a link at `slowestBytesPerSecond` needs for what it has received. A server
                // that hands over a chunk and stalls falls behind that and is given up on, instead of
                // resuming until the build around it has run out of time.
                if received > 0, ContinuousClock.now - startedReading > allowance(forBytes: received) {
                    throw failure ?? REAPICacheError.transferStalled
                }
                if received > before {
                    stalledAttempts = 0
                } else {
                    stalledAttempts += 1
                    guard stalledAttempts <= Self.maximumStalledReadAttempts else {
                        throw failure ?? REAPICacheError.corruptBlob
                    }
                }
                var delay: Duration = .milliseconds(200 + Int.random(in: 0 ... 100))
                if let rpcError = failure as? RPCError, rpcError.code == .resourceExhausted {
                    if let hinted = REAPIBackpressureRetryPolicy.retryInfoDelay(rpcError) {
                        delay = max(delay, hinted)
                    }
                    guard delay <= .seconds(1) - backpressureDelay else { throw rpcError }
                    backpressureDelay += delay
                }
                try await Task.sleep(for: delay)
            }
            let hash = progress.hash
            guard hash == digest.hash else { throw REAPICacheError.corruptBlob }
        } catch {
            try? await fileSystem.remove(AbsolutePath(validating: path.path))
            throw error
        }
    }

    /// A count of requests that may be in flight, handed out in the order they were asked for.
    private final class Permits: Sendable {
        private struct State {
            var available: Int
            var waiting: [CheckedContinuation<Void, Never>] = []
        }

        private let state: Mutex<State>

        init(_ count: Int) {
            state = Mutex(State(available: count))
        }

        func acquire() async {
            await withCheckedContinuation { continuation in
                let granted = state.withLock {
                    guard $0.available > 0 else {
                        $0.waiting.append(continuation)
                        return false
                    }
                    $0.available -= 1
                    return true
                }
                if granted { continuation.resume() }
            }
        }

        func release() {
            let next = state.withLock {
                guard !$0.waiting.isEmpty else {
                    $0.available += 1
                    return nil as CheckedContinuation<Void, Never>?
                }
                return $0.waiting.removeFirst()
            }
            next?.resume()
        }
    }

    /// How much of a blob has been written to its file, and the hash over exactly those bytes, so
    /// that a read resumed after a break continues both.
    private final class ReadProgress: Sendable {
        private struct State {
            var received: Int64 = 0
            var hasher = SHA256()
        }

        private let state = Mutex(State())

        var received: Int64 { state.withLock { $0.received } }
        var hash: String { state.withLock { REAPI.hashString($0.hasher.finalize()) } }

        func consumed(_ data: Data) {
            state.withLock {
                $0.hasher.update(data: data)
                $0.received += Int64(data.count)
            }
        }
    }

    private func readAttempt(
        _ digest: REAPI.Digest,
        from offset: Int64,
        compressed: Bool,
        into handle: FileHandle,
        progress: ReadProgress
    ) async throws {
        let encoding = compressed ? "compressed-blobs/zstd" : "blobs"
        // Bytes a broken attempt wrote but did not count are dropped, so the file, the counter and
        // the hash describe the same prefix of the blob.
        try handle.truncate(atOffset: UInt64(offset))
        try handle.seek(toOffset: UInt64(offset))
        try await withIdleGuard(expectedMessageBytes: Int(guards.largestExpectedMessageBytes)) { heartbeat in
            try await self.withClient { client in
                try await Google_Bytestream_ByteStream.Client(wrapping: client).read(
                    .with {
                        $0.resourceName = "\(self.instanceName)/\(encoding)/\(digest.hash)/\(digest.sizeBytes)"
                        $0.readOffset = offset
                    },
                    metadata: try await self.metadata(), options: self.streamOptions(digest, from: offset)
                ) { response in
                    // `read_offset` names an offset into the uncompressed blob, so a resumed compressed
                    // read arrives as a new zstd stream that its own decoder starts on.
                    let decoder = compressed ? try REAPICompression.Decoder(size: digest.sizeBytes - offset) : nil
                    func consume(_ data: Data) throws {
                        let remaining = digest.sizeBytes - progress.received
                        guard Int64(data.count) <= remaining else { throw REAPICacheError.corruptBlob }
                        try handle.write(contentsOf: data)
                        progress.consumed(data)
                    }
                    for try await message in response.messages {
                        heartbeat(message.data.count)
                        if let decoder { try decoder.decode(message.data, consume: consume) } else { try consume(message.data) }
                    }
                    // A stream that ends early is resumed instead of being called corrupt, so the
                    // decoder is only held to the whole blob once the blob is whole.
                    if progress.received == digest.sizeBytes { try decoder?.finish() }
                }
            }
        }
    }
}
