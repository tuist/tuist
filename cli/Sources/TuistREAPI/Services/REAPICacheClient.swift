import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

public final class REAPICacheClient: REAPICacheStoring, Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let connection: Task<Void, Error>
    private let instanceName: String
    private let accountHandle: String
    private let token: @Sendable () async throws -> String

    public init(
        endpoint: GRPCEndpoint,
        accountHandle: String,
        instanceName: String,
        token: @escaping @Sendable () async throws -> String
    ) throws {
        let transport: HTTP2ClientTransport.Posix = try .http2NIOPosix(
            target: .dns(host: endpoint.host, port: endpoint.port),
            transportSecurity: endpoint.isTLS ? .tls : .plaintext
        )
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
            return try await Build_Bazel_Remote_Execution_V2_ActionCache.Client(wrapping: client).getActionResult(
                .with {
                    $0.instanceName = instanceName
                    $0.actionDigest = digest
                    $0.digestFunction = .sha256
                }, metadata: try await metadata(), options: options
            )
        } catch let error as RPCError where error.code == .notFound {
            return nil
        }
    }

    public func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws {
        try REAPI.validate(digest)
        _ = try await Build_Bazel_Remote_Execution_V2_ActionCache.Client(wrapping: client).updateActionResult(
            .with {
                $0.instanceName = instanceName
                $0.actionDigest = digest
                $0.actionResult = result
                $0.digestFunction = .sha256
            }, metadata: try await metadata(), options: options
        )
    }

    public func uploadBlobs(_ blobs: [REAPI.Digest: URL]) async throws {
        let digests = Array(blobs.keys)
        for digest in digests {
            try REAPI.validate(digest)
        }
        for start in stride(from: 0, to: digests.count, by: 256) {
            let batch = Array(digests[start ..< min(start + 256, digests.count)])
            let response = try await Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.Client(wrapping: client)
                .findMissingBlobs(.with {
                    $0.instanceName = instanceName
                    $0.blobDigests = batch
                    $0.digestFunction = .sha256
                }, metadata: try await metadata(), options: options)
            let missing = Array(Set(response.missingBlobDigests))
            for start in stride(from: 0, to: missing.count, by: 8) {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for digest in missing[start ..< min(start + 8, missing.count)] {
                        guard let path = blobs[digest] else { throw REAPICacheError.invalidDigest }
                        group.addTask { try await self.uploadBlob(digest, from: path) }
                    }
                    try await group.waitForAll()
                }
            }
        }
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
            .write(request: request, options: options)
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
                metadata: try await metadata(), options: options
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
