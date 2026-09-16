import FileSystem
import FileSystemTesting
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf
import Testing
import TuistREAPI

struct REAPICacheClientTests {
    @Test(.inTemporaryDirectory) func streamsBlobsAndUsesStandardActionCacheRPCs() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let state = WireCache()
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext
        )
        let server = GRPCServer(
            transport: transport,
            services: [WireActions(state: state), WireCAS(state: state), WireBytes(state: state)]
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let port = try #require(address.ipv4?.port)
            let client = try REAPICacheClient(
                endpoint: .init(host: "127.0.0.1", explicitPort: port, isTLS: false),
                accountHandle: "account",
                instanceName: "project"
            ) { "token" }
            let path = directory.appending(component: "blob").url
            let data = Data(repeating: 42, count: 2 * 1024 * 1024 + 17)
            try data.write(to: path)
            let digest = REAPI.digest(data)
            let empty = directory.appending(component: "empty").url
            try Data().write(to: empty)
            let emptyDigest = REAPI.digest(Data())
            try await client.uploadBlobs([digest: path, emptyDigest: empty])
            try await client.uploadBlobs([digest: path, emptyDigest: empty])
            #expect(await state.writes == 2)
            let output = directory.appending(component: "download").url
            try await client.downloadBlob(digest, to: output)
            #expect(try Data(contentsOf: output) == data)
            #expect(try await client.actionResult(for: digest) == nil)
            let result = REAPI.ActionResult.with { $0.outputFiles = [.with { $0.path = "output"; $0.digest = digest }] }
            try await client.storeActionResult(result, for: digest)
            #expect(try await client.actionResult(for: digest) == result)
            await state.corrupt(digest)
            await #expect(throws: REAPICacheError.self) {
                try await client.downloadBlob(digest, to: directory.appending(component: "bad").url)
            }
            #expect(!FileManager.default.fileExists(atPath: directory.appending(component: "bad").pathString))
        }
    }
}

private actor WireCache {
    var blobs: [REAPI.Digest: Data] = [:]
    var actions: [REAPI.Digest: REAPI.ActionResult] = [:]
    var writes = 0
    func put(_ data: Data, digest: REAPI.Digest) { blobs[digest] = data; writes += 1 }
    func put(_ result: REAPI.ActionResult, digest: REAPI.Digest) { actions[digest] = result }
    func corrupt(_ digest: REAPI.Digest) { blobs[digest] = Data(repeating: 0, count: Int(digest.sizeBytes)) }
}

private struct WireActions: Build_Bazel_Remote_Execution_V2_ActionCache.ServiceProtocol {
    let state: WireCache
    func getActionResult(
        request: ServerRequest<Build_Bazel_Remote_Execution_V2_GetActionResultRequest>,
        context _: ServerContext
    ) async throws -> ServerResponse<REAPI.ActionResult> {
        #expect(Array(request.metadata[stringValues: "authorization"]).first == "Bearer token")
        #expect(Array(request.metadata[stringValues: "x-tuist-account-handle"]).first == "account")
        #expect(request.message.instanceName == "project")
        #expect(request.message.digestFunction == .sha256)
        guard let result = await state.actions[request.message.actionDigest] else { throw RPCError(
            code: .notFound,
            message: "Missing action"
        ) }
        return ServerResponse(message: result, metadata: [:])
    }

    func updateActionResult(
        request: ServerRequest<Build_Bazel_Remote_Execution_V2_UpdateActionResultRequest>,
        context _: ServerContext
    ) async throws -> ServerResponse<REAPI.ActionResult> {
        #expect(request.message.instanceName == "project")
        #expect(request.message.digestFunction == .sha256)
        await state.put(request.message.actionResult, digest: request.message.actionDigest)
        return ServerResponse(message: request.message.actionResult, metadata: [:])
    }
}

private struct WireCAS: Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.SimpleServiceProtocol {
    let state: WireCache
    func findMissingBlobs(
        request: Build_Bazel_Remote_Execution_V2_FindMissingBlobsRequest,
        context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_FindMissingBlobsResponse {
        #expect(request.instanceName == "project")
        #expect(request.digestFunction == .sha256)
        let present = await state.blobs
        return .with { $0.missingBlobDigests = request.blobDigests.filter { present[$0] == nil } }
    }
}

private struct WireBytes: Google_Bytestream_ByteStream.SimpleServiceProtocol {
    let state: WireCache
    func read(
        request: Google_Bytestream_ReadRequest,
        response: RPCWriter<Google_Bytestream_ReadResponse>,
        context _: ServerContext
    ) async throws {
        let digest = try parse(request.resourceName)
        guard let data = await state.blobs[digest] else { throw RPCError(code: .notFound, message: "Missing blob") }
        for offset in stride(from: 0, to: data.count, by: 16384) {
            try await response.write(.with { $0.data = data.subdata(in: offset ..< min(offset + 16384, data.count)) })
        }
    }

    func write(
        request: RPCAsyncSequence<Google_Bytestream_WriteRequest, any Error>,
        context _: ServerContext
    ) async throws -> Google_Bytestream_WriteResponse {
        var data = Data()
        var digest: REAPI.Digest?
        var finished = false
        for try await message in request {
            #expect(message.writeOffset == data.count)
            #expect(message.data.count <= 1024 * 1024)
            #expect(!finished)
            digest = try parse(message.resourceName)
            data.append(message.data)
            finished = message.finishWrite
        }
        let expected = try #require(digest)
        #expect(finished)
        #expect(REAPI.digest(data) == expected)
        await state.put(data, digest: expected)
        return .with { $0.committedSize = Int64(data.count) }
    }

    private func parse(_ name: String) throws -> REAPI.Digest {
        let parts = name.split(separator: "/")
        #expect(parts.first == "project")
        #expect(parts[parts.count - 3] == "blobs")
        let size = try #require(Int64(parts.last!))
        return .with { $0.hash = String(parts[parts.count - 2]); $0.sizeBytes = size }
    }
}
