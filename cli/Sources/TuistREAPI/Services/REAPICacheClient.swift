import Crypto
import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import Synchronization
import TuistEnvironment

public final class REAPICacheClient: REAPICacheStoring, Sendable { // swiftlint:disable:this type_body_length
    private let clients: [GRPCClient<HTTP2ClientTransport.Posix>]
    private let connections: [Task<Void, Error>]
    private let nextClient = Mutex(0)
    private var client: GRPCClient<HTTP2ClientTransport.Posix> {
        nextClient.withLock { index in
            let client = clients[index]
            index = (index + 1) % clients.count
            return client
        }
    }

    private let instanceName: String
    private let accountHandle: String
    private static let maximumBatchBytes: Int64 = 2 * 1024 * 1024
    private let negotiatedBatchBytes = Mutex<Int64>(maximumBatchBytes)
    private var batchBytes: Int64 { negotiatedBatchBytes.withLock { $0 } }
    private let compression = Mutex((stream: false, batchUpload: false))
    private let fileSystem: FileSysteming
    private let token: @Sendable () async throws -> String

    public init(
        endpoint: GRPCEndpoint,
        accountHandle: String,
        instanceName: String,
        fileSystem: FileSysteming = FileSystem(),
        token: @escaping @Sendable () async throws -> String
    ) async throws {
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
        self.clients = clients
        self.connections = connections
        self.instanceName = instanceName
        self.accountHandle = accountHandle
        self.token = token
        self.fileSystem = fileSystem
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

    public func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult? {
        try REAPI.validate(digest)
        do {
            return try await retry {
                try await Build_Bazel_Remote_Execution_V2_ActionCache.Client(wrapping: client).getActionResult(
                    .with {
                        $0.instanceName = instanceName
                        $0.actionDigest = digest
                        $0.digestFunction = .sha256
                    }, metadata: try await metadata(), options: options
                )
            }
        } catch let error as RPCError where error.code == .notFound {
            return nil
        }
    }

    public func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws {
        try REAPI.validate(digest)
        _ = try await retry {
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

    public func validateCapabilities() async throws {
        var options = options
        options.timeout = .seconds(10)
        let response = try await Build_Bazel_Remote_Execution_V2_Capabilities.Client(wrapping: client).getCapabilities(
            .with { $0.instanceName = instanceName }, metadata: try await metadata(), options: options
        )
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
    }

    private func retry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do { return try await operation() } catch let error as RPCError {
                guard attempt < 2, [.unavailable, .resourceExhausted, .deadlineExceeded].contains(error.code) else { throw error }
                try await Task.sleep(for: .milliseconds((1 << attempt) * 200 + Int.random(in: 0 ... 100)))
                attempt += 1
            }
        }
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
        guard try await uploadAvailableBlobs(blobs).count == blobs.count else { throw REAPICacheError.corruptBlob }
    }

    public func uploadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest> {
        for digest in blobs.keys {
            try REAPI.validate(digest)
        }
        // Missing-blob requests contain only digests, so batch by metadata count, not file size.
        let digests = Array(blobs.keys)
        let queries = stride(from: 0, to: digests.count, by: 1024).map {
            Array(digests[$0 ..< min($0 + 1024, digests.count)])
        }
        let missingBlobs = Mutex<Set<REAPI.Digest>>([])
        let existing = try await transfer(queries) { batch in
            let response = try await self.retry {
                try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.Client(wrapping: self.client)
                    .findMissingBlobs(.with {
                        $0.instanceName = self.instanceName; $0.blobDigests = batch; $0.digestFunction = .sha256
                    }, metadata: try await self.metadata(), options: self.options)
            }
            let missing = Set(response.missingBlobDigests)
            guard missing.isSubset(of: Set(batch)) else { throw REAPICacheError.invalidDigest }
            missingBlobs.withLock { $0.formUnion(missing) }
            return Set(batch).subtracting(missing)
        }
        let uploaded = try await transfer(batches(missingBlobs.withLock { Array($0) })) { batch in
            var successful = Set<REAPI.Digest>()
            if batch.count == 1, let digest = batch.first, digest.sizeBytes > self.batchBytes {
                try await self.retry { try await self.uploadBlob(digest, from: blobs[digest]!) }
                successful.insert(digest)
            } else {
                do {
                    try await self.retry {
                        let pending = Set(batch).subtracting(successful)
                        var requests: [Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsRequest.Request] = []
                        for digest in pending {
                            let data = try await self.fileSystem.readFile(at: AbsolutePath(validating: blobs[digest]!.path))
                            let compressed = self.compression.withLock { $0.batchUpload } && data.count >= REAPICompression
                                .threshold
                                ? try REAPICompression.compress(data) : data
                            requests.append(.with {
                                $0.digest = digest
                                $0.data = compressed.count < data.count ? compressed : data
                                $0.compressor = compressed.count < data.count ? .zstd : .identity
                            })
                        }
                        let result = try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage
                            .Client(wrapping: self.client)
                            .batchUpdateBlobs(.with {
                                $0.instanceName = self.instanceName; $0.digestFunction = .sha256
                                $0.requests = requests
                            }, metadata: try await self.metadata(), options: self.options)
                        successful
                            .formUnion(result.responses.filter { $0.status.code == 0 && pending.contains($0.digest) }
                                .map(\.digest))
                        if result.responses.contains(where: { [4, 8, 14].contains($0.status.code) }) {
                            throw RPCError(code: .resourceExhausted, message: "Cache batch temporarily rejected")
                        }
                    }
                } catch {
                    if error is CancellationError || Task.isCancelled { throw error }
                }
            }
            return successful
        }
        return existing.union(uploaded)
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
        var seen = Set<REAPI.Digest>()
        var ordered = orderedDigests.filter { blobs[$0] != nil && seen.insert($0).inserted }
        ordered.append(contentsOf: blobs.keys.filter { !seen.contains($0) })
        let usesStreams = blobs.keys.contains { $0.sizeBytes > batchBytes }
        return try await transfer(batches(ordered), maxConcurrentTasks: usesStreams ? 8 : 32) { batch in
            if batch.count == 1, let digest = batch.first, digest.sizeBytes > self.batchBytes {
                try await self.retry { try await self.downloadBlob(digest, to: blobs[digest]!) }
                try await onDownloaded(digest)
                return [digest]
            }
            var successful = Set<REAPI.Digest>()
            do {
                try await self.retry {
                    let response = try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage
                        .Client(wrapping: self.client)
                        .batchReadBlobs(.with {
                            $0.instanceName = self.instanceName
                            $0.digests = batch.filter { !successful.contains($0) }
                            $0.acceptableCompressors = [.zstd]
                            $0.digestFunction = .sha256
                        }, metadata: try await self.metadata(), options: self.options)
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
                    if response.responses.contains(where: { [4, 8, 14].contains($0.status.code) }) {
                        throw RPCError(code: .resourceExhausted, message: "Cache batch temporarily rejected")
                    }
                }
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
            }
            return successful
        }
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

    private func streamOptions(_ digest: REAPI.Digest) -> CallOptions {
        var options = options
        options.timeout = .seconds(120 + digest.sizeBytes / (32 * 1024))
        return options
    }

    private func uploadBlob(_ digest: REAPI.Digest, from path: URL) async throws {
        let compressed = compression.withLock { $0.stream } && digest.sizeBytes >= REAPICompression.threshold
        let encoding = compressed ? "compressed-blobs/zstd" : "blobs"
        let resource = "\(instanceName)/uploads/\(UUID().uuidString)/\(encoding)/\(digest.hash)/\(digest.sizeBytes)"
        let sentBytes = Mutex<Int64>(0)
        let request = StreamingClientRequest<Google_Bytestream_WriteRequest>(metadata: try await metadata()) { writer in
            let handle = try FileHandle(forReadingFrom: path)
            defer { try? handle.close() }
            let encoder = compressed ? try REAPICompression.Encoder() : nil
            var offset: Int64 = 0
            var consumed: Int64 = 0
            repeat {
                let input = try handle.read(upToCount: 1024 * 1024) ?? Data()
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
                }
            } while consumed < digest.sizeBytes
        }
        let response = try await Google_Bytestream_ByteStream.Client(wrapping: client)
            .write(request: request, options: streamOptions(digest))
        // REAPI permits -1 when a concurrent compressed upload has already completed.
        guard response.committedSize == (compressed ? sentBytes.withLock { $0 } : digest.sizeBytes)
            || (compressed && response.committedSize == -1) else { throw REAPICacheError.corruptBlob }
    }

    public func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        try REAPI.validate(digest)
        // Streaming owns this temporary file; syncing an empty file before filling it adds no durability.
        try Data().write(to: path)
        do {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            let compressed = compression.withLock { $0.stream } && digest.sizeBytes >= REAPICompression.threshold
            let encoding = compressed ? "compressed-blobs/zstd" : "blobs"
            try await Google_Bytestream_ByteStream.Client(wrapping: client).read(
                .with { $0.resourceName = "\(instanceName)/\(encoding)/\(digest.hash)/\(digest.sizeBytes)" },
                metadata: try await metadata(), options: streamOptions(digest)
            ) { response in
                var received: Int64 = 0
                var hasher = SHA256()
                let decoder = compressed ? try REAPICompression.Decoder(size: digest.sizeBytes) : nil
                func consume(_ data: Data) throws {
                    guard Int64(data.count) <= digest.sizeBytes - received else { throw REAPICacheError.corruptBlob }
                    received += Int64(data.count)
                    hasher.update(data: data)
                    try handle.write(contentsOf: data)
                }
                for try await message in response.messages {
                    if let decoder { try decoder.decode(message.data, consume: consume) } else { try consume(message.data) }
                }
                try decoder?.finish()
                guard received == digest.sizeBytes,
                      REAPI.hashString(hasher.finalize()) == digest.hash
                else { throw REAPICacheError.corruptBlob }
            }
        } catch {
            try? await fileSystem.remove(AbsolutePath(validating: path.path))
            throw error
        }
    }
}
