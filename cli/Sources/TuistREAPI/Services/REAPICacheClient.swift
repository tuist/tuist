import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Synchronization
import TuistEnvironment

public final class REAPICacheClient: REAPICacheStoring, Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let connection: Task<Void, Error>
    private let instanceName: String
    private let accountHandle: String
    private let negotiatedBatchBytes = Mutex<Int64>(2 * 1024 * 1024)
    private var batchBytes: Int64 { negotiatedBatchBytes.withLock { $0 } }
    private let token: @Sendable () async throws -> String

    public init(
        endpoint: GRPCEndpoint,
        accountHandle: String,
        instanceName: String,
        token: @escaping @Sendable () async throws -> String
    ) throws {
        let transport = try REAPITransport.make(endpoint: endpoint)
        let client = GRPCClient(transport: transport)
        self.client = client
        connection = Task { try await client.runConnections() }
        self.instanceName = instanceName
        self.accountHandle = accountHandle
        self.token = token
    }

    deinit {
        client.beginGracefulShutdown()
        connection.cancel()
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
        let advertised = response.cacheCapabilities.maxBatchTotalSizeBytes
        if advertised > 0 { negotiatedBatchBytes.withLock { $0 = min(advertised, 2 * 1024 * 1024) } }
    }

    private func retry<T>(_ operation: () async throws -> T) async throws -> T {
        for attempt in 0 ..< 3 {
            do { return try await operation() } catch let error as RPCError {
                guard attempt < 2, [.unavailable, .resourceExhausted, .deadlineExceeded].contains(error.code) else { throw error }
                try await Task.sleep(for: .milliseconds((1 << attempt) * 200 + Int.random(in: 0 ... 100)))
            }
        }
        throw REAPICacheError.corruptBlob
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
        return try await transfer(batches(Array(blobs.keys))) { batch in
            let response = try await self.retry {
                try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.Client(wrapping: self.client)
                    .findMissingBlobs(.with {
                        $0.instanceName = self.instanceName; $0.blobDigests = batch; $0.digestFunction = .sha256
                    }, metadata: try await self.metadata(), options: self.options)
            }
            let missing = Set(response.missingBlobDigests)
            guard missing.isSubset(of: Set(batch)) else { throw REAPICacheError.invalidDigest }
            var successful = Set(batch).subtracting(missing)
            if missing.isEmpty { return successful }
            if batch.count == 1, let digest = batch.first, digest.sizeBytes > self.batchBytes {
                try await self.retry { try await self.uploadBlob(digest, from: blobs[digest]!) }
                successful.insert(digest)
            } else {
                do {
                    try await self.retry {
                        let pending = missing.subtracting(successful)
                        let result = try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage
                            .Client(wrapping: self.client)
                            .batchUpdateBlobs(.with {
                                $0.instanceName = self.instanceName; $0.digestFunction = .sha256
                                $0.requests = try pending.map { digest in
                                    try .with { $0.digest = digest; $0.data = try Data(contentsOf: blobs[digest]!) }
                                }
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
    }

    public func downloadAvailableBlobs(_ blobs: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest> {
        for digest in blobs.keys {
            try REAPI.validate(digest)
        }
        return try await transfer(batches(Array(blobs.keys))) { batch in
            if batch.count == 1, let digest = batch.first, digest.sizeBytes > self.batchBytes {
                try await self.retry { try await self.downloadBlob(digest, to: blobs[digest]!) }
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
                            $0.digestFunction = .sha256
                        }, metadata: try await self.metadata(), options: self.options)
                    for output in response.responses where output.status.code == 0 {
                        guard batch.contains(output.digest), let path = blobs[output.digest], output.compressor == 0,
                              REAPI.digest(output.data) == output.digest else { continue }
                        try output.data.write(to: path, options: .atomic)
                        successful.insert(output.digest)
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
        operation: @escaping @Sendable ([REAPI.Digest]) async throws -> Set<REAPI.Digest>
    ) async throws -> Set<REAPI.Digest> {
        var successful = Set<REAPI.Digest>()
        for start in stride(from: 0, to: batches.count, by: 8) {
            try await withThrowingTaskGroup(of: Set<REAPI.Digest>.self) { group in
                for batch in batches[start ..< min(start + 8, batches.count)] {
                    group.addTask {
                        do { return try await operation(batch) } catch {
                            if error is CancellationError || Task.isCancelled { throw error }
                            return []
                        }
                    }
                }
                for try await completed in group {
                    successful.formUnion(completed)
                }
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
        let resource = "\(instanceName)/uploads/\(UUID().uuidString)/blobs/\(digest.hash)/\(digest.sizeBytes)"
        let request = StreamingClientRequest<Google_Bytestream_WriteRequest>(metadata: try await metadata()) { writer in
            let handle = try FileHandle(forReadingFrom: path)
            defer { try? handle.close() }
            var offset: Int64 = 0
            repeat {
                let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
                guard !data.isEmpty || offset == digest.sizeBytes else { throw REAPICacheError.corruptBlob }
                let message = Google_Bytestream_WriteRequest.with {
                    $0.resourceName = resource
                    $0.writeOffset = offset
                    $0.data = data
                    $0.finishWrite = offset + Int64(data.count) == digest.sizeBytes
                }
                try await writer.write(message)
                offset += Int64(data.count)
            } while offset < digest.sizeBytes
        }
        let response = try await Google_Bytestream_ByteStream.Client(wrapping: client)
            .write(request: request, options: streamOptions(digest))
        guard response.committedSize == digest.sizeBytes else { throw REAPICacheError.corruptBlob }
    }

    public func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        try REAPI.validate(digest)
        FileManager.default.createFile(atPath: path.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            try await Google_Bytestream_ByteStream.Client(wrapping: client).read(
                .with { $0.resourceName = "\(instanceName)/blobs/\(digest.hash)/\(digest.sizeBytes)" },
                metadata: try await metadata(), options: streamOptions(digest)
            ) { response in
                var received: Int64 = 0
                for try await message in response.messages {
                    received += Int64(message.data.count)
                    guard received <= digest.sizeBytes else { throw REAPICacheError.corruptBlob }
                    try handle.write(contentsOf: message.data)
                }
                guard received == digest.sizeBytes else { throw REAPICacheError.corruptBlob }
            }
            guard try REAPI.digest(file: path) == digest else { throw REAPICacheError.corruptBlob }
        } catch {
            try? FileManager.default.removeItem(at: path)
            throw error
        }
    }
}
