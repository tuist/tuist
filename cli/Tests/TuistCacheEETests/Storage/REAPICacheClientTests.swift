import FileSystem
import FileSystemTesting
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import SwiftProtobuf
import Testing
import TuistCache
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer
@testable import TuistCacheEE
@testable import TuistREAPI

struct REAPICacheClientTests {
    @Test(.inTemporaryDirectory, .withMockedEnvironment(), arguments: ["pem", "der", "bundle"])
    func loadsCustomCertificateThroughFileSystem(format: String) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let path = directory.appending(component: "ca")
        let data: Data
        if format == "der" {
            let base64 = Self.caPEM.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
            data = try #require(Data(base64Encoded: base64))
        } else {
            data = Data((format == "bundle" ? Self.caPEM + "\n" + Self.caPEM : Self.caPEM).utf8)
        }
        try data.write(to: path.url)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CA_CERTIFICATE"] = path.pathString
        _ = try await REAPITransport.make(
            endpoint: .init(host: "cache.example.com", explicitPort: 443, isTLS: true),
            fileSystem: FileSystem()
        )
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment(), arguments: [false, true])
    func rejectsMissingOrInvalidCertificate(invalid: Bool) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let path = directory.appending(component: "ca")
        if invalid { try await FileSystem().writeText("not a certificate", at: path) }
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CA_CERTIFICATE"] = path.pathString
        await #expect(throws: (any Error).self) {
            _ = try await REAPITransport.make(endpoint: .init(host: "cache.example.com", explicitPort: 443, isTLS: true))
        }
    }

    @Test func proxySelectionHonorsBypassAndExplicitDisable() throws {
        let endpoint = GRPCEndpoint(host: "cache.example.com", explicitPort: 443, isTLS: true)
        #expect(try REAPITransport.proxyURL(
            endpoint: endpoint,
            variables: ["HTTPS_PROXY": "http://user:pass@proxy:8080"],
            enabled: true
        )?.port == 8080)
        #expect(try REAPITransport.proxyURL(endpoint: endpoint, variables: ["https_proxy": "https://proxy:8443"], enabled: true)?
            .scheme == "https")
        #expect(try REAPITransport.proxyURL(endpoint: endpoint, variables: ["HTTPS_PROXY": "invalid"], enabled: false) == nil)
        #expect(try REAPITransport.proxyURL(
            endpoint: endpoint,
            variables: ["HTTPS_PROXY": "invalid", "NO_PROXY": ".example.com"],
            enabled: true
        ) == nil)
        #expect(throws: REAPICacheError.unsupportedProxy) {
            try REAPITransport.proxyURL(endpoint: endpoint, variables: ["HTTPS_PROXY": "socks5://proxy:1080"], enabled: true)
        }
    }

    @Test(.inTemporaryDirectory) func streamsBlobsAndUsesStandardActionCacheRPCs() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let state = WireCache()
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext
        )
        let server = GRPCServer(
            transport: transport,
            services: [WireActions(state: state), WireCAS(state: state), WireBytes(state: state), WireCapabilities()]
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let port = try #require(address.ipv4?.port)
            let client = try await REAPICacheClient(
                endpoint: .init(host: "127.0.0.1", explicitPort: port, isTLS: false),
                accountHandle: "account",
                instanceName: "project"
            ) { "token" }
            try await client.validateCapabilities()
            let storage = BinaryCacheStorage(
                selectiveTestsStorage: NoBinaryFallback(),
                local: BinaryCacheLocalStore(
                    directory: directory.appending(component: "Binaries")
                ),
                remote: client
            )
            let coldTargets = Set((0 ..< 1000).map {
                CacheStorableItem(
                    name: "Shared",
                    hash: "target-\($0)",
                    metadata: .init(binaryCacheFingerprints: ["ios-device": "sdk-\($0)"])
                )
            })
            let start = ContinuousClock.now
            #expect(try await storage.fetch(coldTargets, cacheCategory: .binaries).isEmpty)
            print("1000 targets / 2000 real gRPC misses at 50 ms simulated service latency: \(start.duration(to: .now))")
            #expect(await state.actionQueries.count == 2000)
            #expect(await state.actionQueries.values.allSatisfy { $0 == 1 })
            #expect(await state.peakActionQueries > 1)
            #expect(await state.peakActionQueries <= 32)
            var inputs: [REAPI.Digest: URL] = [:]
            for index in 0 ..< 300 {
                let file = directory.appending(component: "small-\(index)").url
                let body = Data(repeating: UInt8(index % 256), count: 1024 + index)
                try body.write(to: file)
                inputs[REAPI.digest(body)] = file
            }
            await state.failNextBatches()
            #expect(try await client.uploadAvailableBlobs(inputs).count == 300)
            #expect(await state.updateCalls > 1)
            #expect(await state.updateCalls < 20)
            #expect(await state.largestBatch <= 32 * 1024)
            let corrupt = try #require(inputs.keys.first)
            await state.corrupt(corrupt)
            var destinations = Dictionary(uniqueKeysWithValues: inputs.keys.map {
                ($0, directory.appending(component: "download-" + $0.hash).url)
            })
            let missing = REAPI.digest(Data("missing".utf8))
            destinations[missing] = directory.appending(component: "missing").url
            let downloaded = try await client.downloadAvailableBlobs(destinations)
            #expect(downloaded == Set(inputs.keys).subtracting([corrupt]))
            #expect(await state.readCalls > 1)
            #expect(await state.readCalls < 20)
            #expect(!FileManager.default.fileExists(atPath: destinations[corrupt]!.path))
            #expect(!FileManager.default.fileExists(atPath: destinations[missing]!.path))
            let path = directory.appending(component: "blob").url
            let data = Data(repeating: 42, count: 2 * 1024 * 1024 + 17)
            try data.write(to: path)
            let digest = REAPI.digest(data)
            let empty = directory.appending(component: "empty").url
            try Data().write(to: empty)
            let emptyDigest = REAPI.digest(Data())
            try await client.uploadBlobs([digest: path, emptyDigest: empty])
            try await client.uploadBlobs([digest: path, emptyDigest: empty])
            #expect(await state.writes == 302)
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

    private static let caPEM = """
    -----BEGIN CERTIFICATE-----
    MIIC1jCCAb6gAwIBAgIJAJlwwm+UwR8bMA0GCSqGSIb3DQEBCwUAMBgxFjAUBgNV
    BAMMDVR1aXN0IFRlc3QgQ0EwHhcNMjYwNzMwMTAyNzQzWhcNMzYwNzI3MTAyNzQz
    WjAYMRYwFAYDVQQDDA1UdWlzdCBUZXN0IENBMIIBIjANBgkqhkiG9w0BAQEFAAOC
    AQ8AMIIBCgKCAQEAqFVEuF4ifFLLwqHbmAq8n85/T48H9EZ+JgeNG/hqPohrEdYV
    xyqVUE3P486kMWiSBvj6DsiE52SYjpQ90UmvmZltgepdy5nas3O+l0PbP4t8RTnT
    UY8jKBd8XmW3/CXnf4UxRMN54SuY8ehsrxHFLjeW3IErDqwhFIT2okPKNRCZTY2t
    aUF5brOCenAA4fkrltFgTY6klIggRr4UtUgQXRqLAgNWH6wxiaqNpP+ObtZjNp5e
    YlgQxcJVkDso3fV+huvdjmh+mIrCmHRtHc6ctNqnH7E4NY6f5e0gURusJV+UX6xS
    T7UlKn0sGL9xUtKNJXnCH/UOOd5nzuENnSFbdwIDAQABoyMwITAPBgNVHRMBAf8E
    BTADAQH/MA4GA1UdDwEB/wQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEAfmPzhf94
    F+CnPseiC6giYtrefx23r9G1P1e1wCSph5atFmdLW6Q2sDeab7LPSQUqnEx1/Q7I
    mYwgPNZExQoxBYla9zvqyC/TWYSR2768oLSwSAqGKa7iN+QiO+fFZJeelXW1Fz2z
    QQEd/RMZPotQMWTtoJ36gSwFrk8SraRT4l8E+iWhOTH+nNmPJWmcq3MPgL0j3aaS
    xuSsMl2S/1JBAVkwnsQt2Ldwxs8si7ACeeneESn1L22jtRiQJAvadurOOvmXYItY
    JJDM29xzYSuzuf7j46+zSYushfZ0faO9E9lp7PrYcUHNI4PPs1a3I/v5rtl1YtA8
    NQOawDBP+hdGwA==
    -----END CERTIFICATE-----
    """
}

private actor WireCache {
    var blobs: [REAPI.Digest: Data] = [:]
    var actions: [REAPI.Digest: REAPI.ActionResult] = [:]
    var actionQueries: [REAPI.Digest: Int] = [:]
    var peakActionQueries = 0
    private var activeActionQueries = 0
    func lookup(_ digest: REAPI.Digest) async throws -> REAPI.ActionResult? {
        actionQueries[digest, default: 0] += 1
        activeActionQueries += 1
        peakActionQueries = max(peakActionQueries, activeActionQueries)
        defer { activeActionQueries -= 1 }
        try await Task.sleep(for: .milliseconds(50))
        return actions[digest]
    }

    var writes = 0
    var updateCalls = 0
    var readCalls = 0
    var largestBatch = 0
    private var failUpdate = false
    private var failRead = false
    func failNextBatches() { failUpdate = true; failRead = true }
    func beginUpdate(bytes: Int) throws {
        updateCalls += 1
        largestBatch = max(largestBatch, bytes)
        if failUpdate { failUpdate = false; throw RPCError(code: .unavailable, message: "Injected transient failure") }
    }

    func beginRead() throws {
        readCalls += 1
        if failRead { failRead = false; throw RPCError(code: .resourceExhausted, message: "Injected transient pressure") }
    }

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
        guard let result = try await state.lookup(request.message.actionDigest) else { throw RPCError(
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
    func batchUpdateBlobs(
        request: Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsRequest,
        context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsResponse {
        try await state.beginUpdate(bytes: request.requests.reduce(0) { $0 + $1.data.count })
        for entry in request.requests {
            await state.put(entry.data, digest: entry.digest)
        }
        return .with { $0.responses = request.requests.map { entry in .with { $0.digest = entry.digest } } }
    }

    func batchReadBlobs(
        request: Build_Bazel_Remote_Execution_V2_BatchReadBlobsRequest,
        context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_BatchReadBlobsResponse {
        try await state.beginRead()
        let blobs = await state.blobs
        return .with { $0.responses = request.digests.map { digest in
            .with { $0.digest = digest; if let data = blobs[digest] { $0.data = data } else { $0.status.code = 5 } }
        } }
    }

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

private struct WireCapabilities: Build_Bazel_Remote_Execution_V2_Capabilities.SimpleServiceProtocol {
    func getCapabilities(
        request _: Build_Bazel_Remote_Execution_V2_GetCapabilitiesRequest,
        context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_ServerCapabilities {
        .with {
            $0.cacheCapabilities.digestFunctions = [.sha256]
            $0.cacheCapabilities.maxBatchTotalSizeBytes = 32 * 1024
        }
    }
}

private struct NoBinaryFallback: CacheStoring {
    func fetch(_: Set<CacheStorableItem>, cacheCategory _: RemoteCacheCategory) async throws -> [CacheItem: AbsolutePath] {
        Issue.record("Binary lookup reached the selective-test delegate")
        return [:]
    }

    func store(_: [CacheStorableItem: [AbsolutePath]], cacheCategory _: RemoteCacheCategory) async throws -> [CacheStorableItem] {
        Issue.record("Binary store reached the selective-test delegate")
        return []
    }
}
