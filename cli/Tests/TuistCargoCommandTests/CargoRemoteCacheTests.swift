import FileSystem
import FileSystemTesting
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Synchronization
import Testing
@testable import TuistCargoCommand
@testable import TuistREAPI

struct CargoRemoteCacheTests {
    @Test(.inTemporaryDirectory, arguments: [false, true])
    func metadataRetriesSurviveTheRelayWatchdog(drain: Bool) async throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let token = root.appendingPathComponent("token")
        try Data("token".utf8).write(to: token)
        let expected = REAPI.ActionResult.with { $0.stdoutRaw = Data("cached after retry".utf8) }
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext
        )
        let server = GRPCServer(transport: transport, services: [
            CargoWireCapabilities(compression: false), CargoWireActions(result: expected, drain: drain),
        ])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let port = try #require(try await transport.listeningAddress.ipv4?.port)
            let remote = try #require(await CargoCompilerObserver.remote([
                "TUIST_CARGO_CACHE_REMOTE_URL": "http://127.0.0.1:\(port)",
                "TUIST_CARGO_CACHE_NAMESPACE": "account/project", "TUIST_CARGO_CACHE_TOKEN_FILE": token.path,
            ]))
            try await withBroker(remote: remote) { cache, root in
                #expect(try await cache.actionResult(for: REAPI.emptyBlob) == expected)
                #expect(try await cache.containsActionResult(for: REAPI.digest(Data("presence".utf8))))
                try await Self.waitUntil { (try? Self.pendingFiles(root.appendingPathComponent("broker")).isEmpty) == true }
            }
        }
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func waitsForConnectionPreparationWithoutSpendingTheMetadataDeadline(cancel: Bool) async throws {
        let root = try directory()
        let broker = root.appendingPathComponent("broker")
        let remote = BrokerMemoryCache()
        let service = Task {
            try await CargoRemoteCache.serve(directory: broker, prepare: {
                try await Task.sleep(for: .milliseconds(1200))
                return remote
            })
        }
        defer { service.cancel() }
        try await Self.waitUntil { FileManager.default.fileExists(atPath: broker.appendingPathComponent("server.json").path) }
        let lookup = Task { try await CargoRemoteCache(directory: broker).actionResult(for: REAPI.emptyBlob) }
        defer { lookup.cancel() }
        if cancel {
            service.cancel()
            await #expect(throws: CancellationError.self) { try await service.value }
            await #expect(throws: (any Error).self) { try await lookup.value }
        } else {
            #expect(try await lookup.value == nil)
            service.cancel()
            await #expect(throws: CancellationError.self) { try await service.value }
        }
        #expect(!FileManager.default.fileExists(atPath: broker.appendingPathComponent("server.json").path))
        #expect(try Self.pendingFiles(broker).isEmpty)
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func negotiatesCompressionBeforeRestoringRemoteArtifacts(compression: Bool) async throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let token = root.appendingPathComponent("token")
        try Data("token".utf8).write(to: token)
        let data = Data(repeating: 42, count: 16384)
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext
        )
        let server = GRPCServer(transport: transport, services: [
            CargoWireCapabilities(compression: compression), CargoWireBytes(data: data, compression: compression),
        ])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let port = try #require(address.ipv4?.port)
            let remote = try #require(await CargoCompilerObserver.remote([
                "TUIST_CARGO_CACHE_REMOTE_URL": "http://127.0.0.1:\(port)",
                "TUIST_CARGO_CACHE_NAMESPACE": "account/project", "TUIST_CARGO_CACHE_TOKEN_FILE": token.path,
            ]))
            let destination = root.appendingPathComponent("restored")
            try await remote.downloadBlob(REAPI.digest(data), to: destination)
            #expect(try Data(contentsOf: destination) == data)
        }
    }

    @Test(.inTemporaryDirectory, arguments: ["retained", "corrupt", "evicted", "unwritable", "denied", "unavailable"])
    func reusesVerifiedChunksAcrossArtifactVersionsAndClientRestarts(mode: String) async throws {
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let token = root.appendingPathComponent("token")
        try Data("token".utf8).write(to: token)
        let cache = root.appendingPathComponent("cache")
        let blobs = cache.appendingPathComponent("blobs")
        let parts = (1 ... 4).map { Data(repeating: UInt8($0), count: 1024 * 1024) }
        let original = parts[0] + parts[1] + parts[0] + parts[2]
        let edited = parts[0] + parts[3] + parts[0] + parts[2]
        let wire = CargoChunkWireCAS(
            recipes: [
                REAPI.digest(original): [parts[0], parts[1], parts[0], parts[2]],
                REAPI.digest(edited): [parts[0], parts[3], parts[0], parts[2]],
            ],
            parts: parts
        )
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext
        )
        let server = GRPCServer(
            transport: transport,
            services: [CargoWireCapabilities(compression: false, splitting: true), wire]
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let port = try #require(try await transport.listeningAddress.ipv4?.port)
            func restore(_ data: Data, rejected: Bool = false) async throws {
                // Each restore creates a new transport; only the caller-owned disk cache survives.
                let remote = try #require(await CargoCompilerObserver.remote([
                    "TUIST_CARGO_CACHE_REMOTE_URL": "http://127.0.0.1:\(port)",
                    "TUIST_CARGO_CACHE_NAMESPACE": "account/project", "TUIST_CARGO_CACHE_TOKEN_FILE": token.path,
                    "TUIST_CARGO_CACHE_DIR": cache.path,
                ]))
                let destination = root.appendingPathComponent(UUID().uuidString)
                let digest = REAPI.digest(data)
                let result = try await remote.downloadBlobs([digest: destination])
                #expect(result.available == (rejected ? [] : [digest]))
                #expect(result.remoteFailures == (rejected ? [digest] : []))
                if rejected {
                    #expect(!FileManager.default.fileExists(atPath: destination.path))
                } else {
                    #expect(try Data(contentsOf: destination) == data)
                }
            }
            try await restore(original)
            #expect(await wire.downloadedBytes == 3 * 1024 * 1024)
            if mode == "corrupt" {
                try Data(repeating: 9, count: parts[0].count).write(to: blobs.appendingPathComponent(REAPI.digest(parts[0]).hash))
            } else if mode == "evicted" {
                try FileManager.default.removeItem(at: blobs.appendingPathComponent(REAPI.digest(parts[0]).hash))
            } else if mode == "unwritable" {
                try FileManager.default.removeItem(at: blobs)
                try Data("not a directory".utf8).write(to: blobs)
            }
            let before = await wire.downloadedBytes
            try await restore(edited)
            let expectedBytes = mode == "unwritable" ? 3 * 1024 * 1024 :
                ["corrupt", "evicted"].contains(mode) ? 2 * 1024 * 1024 : 1024 * 1024
            #expect(await wire.downloadedBytes - before == expectedBytes)
            let after = await wire.downloadedBytes
            try await restore(edited)
            #expect(await wire.downloadedBytes - after == (mode == "unwritable" ? 3 * 1024 * 1024 : 0))
            if ["denied", "unavailable"].contains(mode) {
                await wire.rejectSplits(with: mode == "denied" ? .permissionDenied : .unavailable)
                try await restore(edited, rejected: true)
                #expect(await wire.downloadedBytes == after)
            }
        }
    }

    private static let downloadCases = [16384, 3 * 1024 * 1024].flatMap { size in [
        "missing", "corrupt", "unavailable", "local", "recovered", "missing-after-retry", "corrupt-after-retry",
        "local-after-retry", "chunk-internal", "mixed", "split-rejected", "rpc", "rpc-after-status",
    ].filter { size == 16384 || !["local-after-retry", "rpc-after-status"].contains($0) }.map { (size, $0) } }

    @Test(.inTemporaryDirectory, arguments: Self.downloadCases)
    func distinguishesEntryLossFromDownloadOutages(scenario: (Int, String)) async throws {
        let (size, mode) = scenario
        let root = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let token = root.appendingPathComponent("token")
        try Data("token".utf8).write(to: token)
        let expected = Data(repeating: 42, count: size)
        let missing = REAPI.digest(Data("missing".utf8))
        let data = mode.hasPrefix("corrupt") ? Data(repeating: 24, count: size) : expected
        let retry = mode.hasSuffix("-after-retry") || ["recovered", "rpc-after-status"].contains(mode)
        let status: Int32 = mode.hasPrefix("missing") ? 5 : mode == "chunk-internal" ? 13 : 14
        let failure = CargoWireFailure(
            code: retry ? 14 : status,
            remaining: retry ? 1 : ["missing", "unavailable", "chunk-internal", "mixed"].contains(mode) ? .max : 0,
            after: mode.hasSuffix("-after-retry") && mode.hasPrefix("missing") ? 5 : 0,
            rpcFailure: mode.hasPrefix("rpc")
        )
        let transport: HTTP2ServerTransport.Posix = .http2NIOPosix(
            address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext
        )
        let server = GRPCServer(transport: transport, services: [
            CargoWireCapabilities(compression: false, splitting: ["chunk-internal", "split-rejected"].contains(mode)),
            CargoWireCAS(
                data: data,
                failure: failure,
                missing: mode == "mixed" ? missing : nil,
                rejectSplit: mode == "split-rejected"
            ),
            CargoWireBytes(data: data, compression: false, failure: mode == "chunk-internal" ? nil : failure),
        ])
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }
            let address = try await transport.listeningAddress
            let port = try #require(address.ipv4?.port)
            let remote = try #require(await CargoCompilerObserver.remote([
                "TUIST_CARGO_CACHE_REMOTE_URL": "http://127.0.0.1:\(port)",
                "TUIST_CARGO_CACHE_NAMESPACE": "account/project", "TUIST_CARGO_CACHE_TOKEN_FILE": token.path,
            ]))
            try await withBroker(remote: remote) { cache, root in
                let digest = REAPI.digest(expected)
                let path = root.appendingPathComponent(mode.hasPrefix("local") ? "absent/artifact" : "artifact")
                var files = [digest: path]
                if mode == "mixed" { files[missing] = root.appendingPathComponent("missing") }
                let result = try await cache.downloadBlobs(files)
                #expect(result.available == (["recovered", "split-rejected"].contains(mode) ? [digest] : []))
                #expect(result.remoteFailures == (
                    ["unavailable", "chunk-internal", "mixed", "rpc", "rpc-after-status"].contains(mode) ? [digest] : []
                ))
                if ["recovered", "split-rejected"].contains(mode) { #expect(try Data(contentsOf: path) == expected) }
            }
        }
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func relaysCacheOperationsAndPartialUploadOutcomes(knownUploads: Bool) async throws {
        let remote = BrokerMemoryCache(knownUploads: knownUploads)
        try await withBroker(remote: remote) { cache, root in
            let data = Data("artifact".utf8)
            let digest = REAPI.digest(data)
            let source = root.appendingPathComponent("source")
            try data.write(to: source)
            #expect(try await cache.actionResult(for: digest) == nil)
            #expect(try await !cache.containsActionResult(for: digest))
            let result = REAPI.ActionResult.with {
                $0.stderrRaw = Data("diagnostic".utf8)
                $0.outputFiles = [.with { $0.path = "artifact"; $0.digest = digest }]
                $0.outputSymlinks = [.with { $0.path = "link"; $0.target = "artifact" }]
            }
            try await cache.storeActionResult(result, for: digest)
            #expect(try await cache.actionResult(for: digest) == result)
            #expect(try await cache.containsActionResult(for: digest))

            let upload = try await cache.uploadAvailableBlobs([digest: source, BrokerMemoryCache.rejected: source])
            #expect(upload.available == [digest])
            #expect(upload.failures == [BrokerMemoryCache.rejected: "permission denied"])
            #expect(upload.uploaded == (knownUploads ? [digest] : nil))
            let empty = try await cache.uploadAvailableBlobs([:])
            #expect(empty.uploaded == (knownUploads ? [] : nil))
            try await cache.uploadBlobs([digest: source])
            await #expect(throws: (any Error).self) {
                try await cache.uploadBlobs([BrokerMemoryCache.rejected: source])
            }
            #expect(await remote.requiredUploads == 2)

            let destination = root.appendingPathComponent("download")
            let missing = REAPI.digest(Data("missing".utf8))
            let available = try await cache.downloadAvailableBlobs([
                digest: destination, missing: root.appendingPathComponent("missing"),
            ])
            #expect(available == [digest])
            #expect(try Data(contentsOf: destination) == data)
            let single = root.appendingPathComponent("single")
            try await cache.downloadBlob(digest, to: single)
            #expect(try Data(contentsOf: single) == data)
            try await Self.waitUntil { (try? Self.pendingFiles(root.appendingPathComponent("broker")).isEmpty) == true }
        }
    }

    @Test(.inTemporaryDirectory)
    func servesMetadataAndDownloadsWhilePublicationsAreSaturated() async throws {
        let remote = BrokerMemoryCache(synchronizeReads: true, blockUploads: true)
        try await withBroker(remote: remote) { cache, root in
            let uploads = (0 ..< 24).map { _ in Task { try await cache.uploadBlobs([:]) } }
            defer { uploads.forEach { $0.cancel() } }
            let broker = root.appendingPathComponent("broker")
            try await Self.waitUntil {
                let pending = (try? Self.pendingFiles(broker).filter { $0.hasSuffix(".request") }.count) ?? 0
                return await remote.activeUploads == 8 && pending == 8
            }
            let other = CargoRemoteCache(directory: broker)
            async let first = cache.actionResult(for: REAPI.emptyBlob)
            async let second = other.actionResult(for: REAPI.emptyBlob)
            let values = try await (first, second)
            #expect(values.0 == nil && values.1 == nil)
            #expect(await remote.peakReads == 2)
            let destination = root.appendingPathComponent("download-during-uploads")
            let download = Task { try await cache.downloadAvailableBlobs([REAPI.emptyBlob: destination]) }
            defer { download.cancel() }
            try await Self.waitUntil { FileManager.default.fileExists(atPath: destination.path) }
            #expect(try await download.value == [REAPI.emptyBlob])
            #expect(try Data(contentsOf: destination).isEmpty)
            await remote.releaseUploads()
            for upload in uploads {
                try await upload.value
            }
            #expect(await remote.peakUploads == 8)
            try await Self.waitUntil { (try? Self.pendingFiles(broker).isEmpty) == true }
        }
    }

    @Test(.inTemporaryDirectory)
    func concurrentLookupsWaitWithoutSpendingTheirRemoteTimeout() async throws {
        let remote = BrokerMemoryCache(readDelay: .milliseconds(600))
        try await withBroker(remote: remote) { cache, root in
            let expected = REAPI.ActionResult.with { $0.stdoutRaw = Data("cached result".utf8) }
            try await cache.storeActionResult(expected, for: REAPI.emptyBlob)
            try await withThrowingTaskGroup(of: REAPI.ActionResult?.self) { group in
                for _ in 0 ..< 24 {
                    group.addTask { try await cache.actionResult(for: REAPI.emptyBlob) }
                }
                var results = 0
                for try await result in group {
                    #expect(result == expected)
                    results += 1
                }
                #expect(results == 24)
            }
            #expect(await remote.peakReads == 8)
            try await Self.waitUntil { (try? Self.pendingFiles(root.appendingPathComponent("broker")).isEmpty) == true }
        }
    }

    @Test(.inTemporaryDirectory)
    func localDispatchDoesNotConsumeTheBackendDeadline() async throws {
        let root = try directory()
        let broker = root.appendingPathComponent("broker")
        try JSONSerialization.data(withJSONObject: [
            "process": ProcessInfo.processInfo.processIdentifier, "identity": UUID().uuidString,
        ]).write(to: broker.appendingPathComponent("server.json"))
        let expected = REAPI.ActionResult.with { $0.stdoutRaw = Data("cached result".utf8) }
        let response = try JSONSerialization.data(withJSONObject: [
            "result": expected.serializedData().base64EncodedString(), "available": [], "failures": [],
        ])
        let start = ContinuousClock.now
        let now = Mutex(start)
        let acceptedAt = start + .milliseconds(300)
        let allowance = REAPICacheClient.metadataReadAllowance(timeout: CargoRemoteCache.metadataTimeout) + .seconds(1)
        let beforeResponse = start + allowance + .milliseconds(100)
        let deliveredAt = start + allowance + .milliseconds(200)
        let timing = CargoRemoteCache.Timing(now: { now.withLock { $0 } }, sleep: { _ in
            try Task.checkCancellation()
            let instant = now.withLock { instant in
                if instant < acceptedAt { instant = acceptedAt }
                else if instant < beforeResponse { instant = beforeResponse }
                else { instant = deliveredAt }
                return instant
            }
            let name = try #require(FileManager.default.contentsOfDirectory(atPath: broker.path).first {
                $0.hasSuffix(".request")
            })
            let request = broker.appendingPathComponent(name).deletingPathExtension()
            if instant == acceptedAt {
                try Data("\"actionResult\"".utf8).write(to: request.appendingPathExtension("active"), options: .atomic)
            } else if instant == deliveredAt {
                try response.write(to: request.appendingPathExtension("response"), options: .atomic)
            }
        })
        // Poll beyond a budget started at publication, but deliver within the budget started at acceptance.
        let result = try await CargoRemoteCache.$timing.withValue(timing) {
            try await CargoRemoteCache(directory: broker).actionResult(for: REAPI.emptyBlob)
        }
        #expect(result == expected)
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func localRequestRejectionDoesNotMarkTheEndpointUnavailable(obstructAcceptance: Bool) async throws {
        let broker = try directory().appendingPathComponent("broker")
        try JSONSerialization.data(withJSONObject: [
            "process": ProcessInfo.processInfo.processIdentifier, "identity": UUID().uuidString,
        ]).write(to: broker.appendingPathComponent("server.json"))
        let cache = CargoRemoteCache(directory: broker)
        let read = Task { try await cache.actionResult(for: REAPI.emptyBlob) }
        defer { read.cancel() }
        try await Self.waitUntil { (try? Self.pendingFiles(broker).count) == 1 }
        let request = broker.appendingPathComponent(try #require(Self.pendingFiles(broker).first))
        if obstructAcceptance {
            try FileManager.default.createDirectory(
                at: request.deletingPathExtension().appendingPathExtension("active"), withIntermediateDirectories: false
            )
        } else {
            try FileManager.default.removeItem(at: request)
        }
        do {
            _ = try await read.value
            Issue.record("A locally rejected request succeeded")
        } catch {
            #expect(CargoRemoteCache.isOverloaded(error))
        }
    }

    @Test(.inTemporaryDirectory)
    func oneReservationWriteFailureDoesNotStopTheBroker() async throws {
        try await withBroker(remote: BrokerMemoryCache()) { cache, root in
            let expected = REAPI.ActionResult.with { $0.stdoutRaw = Data("cached result".utf8) }
            try await cache.storeActionResult(expected, for: REAPI.emptyBlob)
            let broker = root.appendingPathComponent("broker")
            let id = UUID().uuidString
            let obstruction = broker.appendingPathComponent(id + ".active")
            try FileManager.default.createDirectory(at: obstruction, withIntermediateDirectories: false)
            try Data().write(to: obstruction.appendingPathComponent("not-empty"))
            let request = broker.appendingPathComponent(id + ".request")
            try JSONSerialization.data(withJSONObject: [
                "process": ProcessInfo.processInfo.processIdentifier, "operation": "actionResult",
                "digest": REAPI.emptyBlob.serializedData().base64EncodedString(), "blobs": [],
            ]).write(to: request, options: .atomic)
            try await Self.waitUntil { !FileManager.default.fileExists(atPath: request.path) }
            #expect(try await cache.actionResult(for: REAPI.emptyBlob) == expected)
            try FileManager.default.removeItem(at: obstruction)
        }
    }

    @Test(.inTemporaryDirectory)
    func cancelledReadsRetainCapacityUntilBackendCleanupFinishes() async throws {
        let remote = BrokerMemoryCache(
            blockReads: true, readDelay: .milliseconds(600), readCancellationDelay: .milliseconds(500)
        )
        try await withBroker(remote: remote) { cache, root in
            let expected = REAPI.ActionResult.with { $0.stdoutRaw = Data("cached result".utf8) }
            try await cache.storeActionResult(expected, for: REAPI.emptyBlob)
            let first = (0 ..< 8).map { _ in Task { try await cache.actionResult(for: REAPI.emptyBlob) } }
            defer { first.forEach { $0.cancel() } }
            try await Self.waitUntil { await remote.peakReads == 8 }
            let replacements = (0 ..< 8).map { _ in Task { try await cache.actionResult(for: REAPI.emptyBlob) } }
            defer { replacements.forEach { $0.cancel() } }
            await remote.releaseReads()
            first.forEach { $0.cancel() }
            for read in first {
                await #expect(throws: CancellationError.self) { try await read.value }
            }
            for read in replacements {
                #expect(try await read.value == expected)
            }
            #expect(await remote.peakReads == 8)
            #expect(await remote.cancelledOperations == 8)
            try await Self.waitUntil { (try? Self.pendingFiles(root.appendingPathComponent("broker")).isEmpty) == true }
        }
    }

    @Test(.inTemporaryDirectory)
    func boundsStalledMetadataReadsAndCleansTheirMessages() async throws {
        let remote = BrokerMemoryCache(blockReads: true)
        try await withBroker(remote: remote) { cache, root in
            let started = ContinuousClock.now
            await #expect(throws: (any Error).self) { try await cache.actionResult(for: REAPI.emptyBlob) }
            #expect(started.duration(to: .now) < .seconds(13))
            try await Self.waitUntil { await remote.cancelledOperations == 1 }
            try await Self.waitUntil { (try? Self.pendingFiles(root.appendingPathComponent("broker")).isEmpty) == true }
        }
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func cancellationStopsPendingTransfersAndCleansMessages(cancelServer: Bool) async throws {
        let root = try directory()
        let broker = root.appendingPathComponent("broker")
        let remote = BrokerMemoryCache(blockUploads: true)
        let service = Task { try await CargoRemoteCache.serve(directory: broker, remote: remote) }
        let uploads = (0 ..< 24).map { _ in Task { try await CargoRemoteCache(directory: broker).uploadBlobs([:]) } }
        do {
            try await Self.waitUntil { await remote.activeUploads == 8 }
            if cancelServer { service.cancel() } else { uploads.forEach { $0.cancel() } }
            for upload in uploads {
                if cancelServer {
                    await #expect(throws: (any Error).self) { try await upload.value }
                } else {
                    await #expect(throws: CancellationError.self) { try await upload.value }
                }
            }
            try await Self.waitUntil { await remote.cancelledOperations == 8 }
            service.cancel()
            await #expect(throws: CancellationError.self) { try await service.value }
            #expect(try Self.pendingFiles(broker).isEmpty)
        } catch {
            uploads.forEach { $0.cancel() }
            service.cancel()
            for upload in uploads {
                _ = await upload.result
            }
            _ = await service.result
            throw error
        }
    }

    private func directory() throws -> URL {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let root = URL(fileURLWithPath: directory.pathString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("broker"), withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func withBroker(
        remote: any REAPICacheStoring,
        body: @escaping @Sendable (CargoRemoteCache, URL) async throws -> Void
    ) async throws {
        let root = try directory()
        let broker = root.appendingPathComponent("broker")
        // These tests exercise lane admission and backend cleanup, not client delivery deadlines.
        // Keep executor scheduling delays out of that clock; deadline tests control it separately.
        let now = CargoRemoteCache.timing.now()
        let timing = CargoRemoteCache.Timing(now: { now }, sleep: CargoRemoteCache.timing.sleep)
        try await CargoRemoteCache.$timing.withValue(timing) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                defer { group.cancelAll() }
                group.addTask { try await CargoRemoteCache.serve(directory: broker, remote: remote) }
                group.addTask { try await body(CargoRemoteCache(directory: broker), root) }
                try await group.next()
            }
        }
        #expect(!FileManager.default.fileExists(atPath: broker.appendingPathComponent("server.json").path))
    }

    private static func pendingFiles(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
            $0.hasSuffix(".request") || $0.hasSuffix(".response") || $0.hasSuffix(".active") || $0.hasSuffix(".tmp")
        }
    }

    private static func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while await !condition() {
            try #require(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor CargoWireActions: Build_Bazel_Remote_Execution_V2_ActionCache.SimpleServiceProtocol {
    let result: REAPI.ActionResult
    let drain: Bool
    private var attempts: [REAPI.Digest: Int] = [:]

    init(result: REAPI.ActionResult, drain: Bool) {
        self.result = result
        self.drain = drain
    }

    func getActionResult(
        request: Build_Bazel_Remote_Execution_V2_GetActionResultRequest, context _: ServerContext
    ) async throws -> REAPI.ActionResult {
        #expect(request.instanceName == "project")
        attempts[request.actionDigest, default: 0] += 1
        let attempt = attempts[request.actionDigest, default: 0]
        if drain, attempt <= 5 {
            throw RPCError(code: .unavailable, message: "server is draining")
        }
        if !drain, attempt == 1 {
            // Exceed the real client's per-RPC deadline, not an injected local error.
            try await Task.sleep(for: .seconds(2))
        }
        return result
    }

    func updateActionResult(
        request _: Build_Bazel_Remote_Execution_V2_UpdateActionResultRequest, context _: ServerContext
    ) async throws -> REAPI.ActionResult {
        throw RPCError(code: .unimplemented, message: "Read only")
    }
}

private struct CargoWireCapabilities: Build_Bazel_Remote_Execution_V2_Capabilities.SimpleServiceProtocol {
    let compression: Bool
    var splitting = false

    func getCapabilities(
        request: Build_Bazel_Remote_Execution_V2_GetCapabilitiesRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_ServerCapabilities {
        #expect(request.instanceName == "project")
        return .with {
            $0.cacheCapabilities.digestFunctions = [.sha256]
            $0.cacheCapabilities.supportedCompressors = compression ? [.zstd] : []
            $0.cacheCapabilities.splitBlobSupport = splitting
        }
    }
}

private struct CargoWireBytes: Google_Bytestream_ByteStream.SimpleServiceProtocol {
    let data: Data
    let compression: Bool
    var failure: CargoWireFailure?

    func read(
        request: Google_Bytestream_ReadRequest, response: RPCWriter<Google_Bytestream_ReadResponse>, context _: ServerContext
    ) async throws {
        let status = try await failure?.next() ?? 0
        if status != 0 { throw RPCError(code: status == 5 ? .notFound : .unavailable, message: "Injected read failure") }
        let compressed = request.resourceName.contains("/compressed-blobs/zstd/")
        #expect(compressed == compression)
        let bytes = try compressed ? REAPICompression.compress(data) : data
        try await response.write(.with { $0.data = bytes })
    }

    func write(
        request _: RPCAsyncSequence<Google_Bytestream_WriteRequest, any Error>, context _: ServerContext
    ) async throws -> Google_Bytestream_WriteResponse {
        throw RPCError(code: .unimplemented, message: "Read-only fixture")
    }
}

private actor CargoWireFailure {
    let code: Int32
    var remaining: Int
    let after: Int32
    let rpcFailure: Bool

    init(code: Int32, remaining: Int, after: Int32 = 0, rpcFailure: Bool = false) {
        self.code = code; self.remaining = remaining; self.after = after; self.rpcFailure = rpcFailure
    }

    func next() throws -> Int32 {
        if remaining == 0, rpcFailure { throw RPCError(code: .unavailable, message: "Injected RPC failure") }
        guard remaining > 0 else { return after }
        remaining -= 1
        return code
    }
}

private actor CargoChunkWireCAS: Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.SimpleServiceProtocol {
    let recipes: [REAPI.Digest: [Data]]
    let parts: [REAPI.Digest: Data]
    private(set) var downloadedBytes = 0
    private var splitFailure: RPCError.Code?

    init(recipes: [REAPI.Digest: [Data]], parts: [Data]) {
        self.recipes = recipes
        self.parts = Dictionary(uniqueKeysWithValues: parts.map { (REAPI.digest($0), $0) })
    }

    func rejectSplits(with code: RPCError.Code) {
        splitFailure = code
    }

    func batchReadBlobs(
        request: Build_Bazel_Remote_Execution_V2_BatchReadBlobsRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_BatchReadBlobsResponse {
        #expect(request.instanceName == "project")
        var result = Build_Bazel_Remote_Execution_V2_BatchReadBlobsResponse()
        for digest in request.digests {
            let data = parts[digest] ?? Data()
            let encoded = try REAPICompression.compress(data)
            downloadedBytes += data.count
            result.responses.append(.with {
                $0.digest = digest; $0.data = encoded; $0.compressor = .zstd; $0.status.code = parts[digest] == nil ? 5 : 0
            })
        }
        return result
    }

    func splitBlob(
        request: Build_Bazel_Remote_Execution_V2_SplitBlobRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_SplitBlobResponse {
        if let splitFailure { throw RPCError(code: splitFailure, message: "Injected split failure") }
        guard let parts = recipes[request.blobDigest] else { throw RPCError(code: .notFound, message: "Unknown blob") }
        return .with { $0.chunkDigests = parts.map(REAPI.digest) }
    }

    func batchUpdateBlobs(
        request _: Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsResponse {
        throw RPCError(code: .unimplemented, message: "Read only")
    }

    func findMissingBlobs(
        request _: Build_Bazel_Remote_Execution_V2_FindMissingBlobsRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_FindMissingBlobsResponse {
        throw RPCError(code: .unimplemented, message: "Read only")
    }

    func spliceBlob(
        request _: Build_Bazel_Remote_Execution_V2_SpliceBlobRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_SpliceBlobResponse {
        throw RPCError(code: .unimplemented, message: "Read only")
    }
}

private struct CargoWireCAS: Build_Bazel_Remote_Execution_V2_ContentAddressableStorage.SimpleServiceProtocol {
    let data: Data
    let failure: CargoWireFailure
    var missing: REAPI.Digest?
    var rejectSplit = false

    func batchReadBlobs(
        request: Build_Bazel_Remote_Execution_V2_BatchReadBlobsRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_BatchReadBlobsResponse {
        let code = try await failure.next()
        return .with { result in
            result.responses = request.digests.map { digest in
                .with {
                    $0.digest = digest; $0.status.code = digest == missing ? 5 : code
                    $0.data = $0.status.code == 0 ? Data(data.prefix(Int(digest.sizeBytes))) : Data()
                }
            }
        }
    }

    func batchUpdateBlobs(
        request _: Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_BatchUpdateBlobsResponse { throw RPCError(
        code: .unimplemented,
        message: "Read only"
    ) }

    func findMissingBlobs(
        request _: Build_Bazel_Remote_Execution_V2_FindMissingBlobsRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_FindMissingBlobsResponse { throw RPCError(
        code: .unimplemented,
        message: "Read only"
    ) }

    func splitBlob(
        request _: Build_Bazel_Remote_Execution_V2_SplitBlobRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_SplitBlobResponse {
        if rejectSplit { throw RPCError(code: .invalidArgument, message: "Chunking unavailable for this blob") }
        return .with { $0.chunkDigests = Array(repeating: REAPI.digest(Data(data.prefix(1024 * 1024))), count: 3) }
    }

    func spliceBlob(
        request _: Build_Bazel_Remote_Execution_V2_SpliceBlobRequest, context _: ServerContext
    ) async throws -> Build_Bazel_Remote_Execution_V2_SpliceBlobResponse { throw RPCError(
        code: .unimplemented,
        message: "Read only"
    ) }
}

private actor BrokerMemoryCache: REAPICacheStoring {
    static let rejected = REAPI.digest(Data("rejected".utf8))
    private let knownUploads: Bool
    private let synchronizeReads: Bool
    private var blockReads: Bool
    private var blockUploads: Bool
    private let readDelay: Duration
    private let readCancellationDelay: Duration
    private var result: REAPI.ActionResult?
    private var blobs: [REAPI.Digest: Data] = [REAPI.emptyBlob: Data()]
    private var reads = 0
    private(set) var peakReads = 0
    private(set) var requiredUploads = 0
    private(set) var cancelledOperations = 0
    private(set) var activeUploads = 0
    private(set) var peakUploads = 0

    init(
        knownUploads: Bool = false, synchronizeReads: Bool = false, blockReads: Bool = false,
        blockUploads: Bool = false, readDelay: Duration = .zero, readCancellationDelay: Duration = .zero
    ) {
        self.knownUploads = knownUploads
        self.synchronizeReads = synchronizeReads
        self.blockReads = blockReads
        self.blockUploads = blockUploads
        self.readDelay = readDelay
        self.readCancellationDelay = readCancellationDelay
    }

    func actionResult(for _: REAPI.Digest) async throws -> REAPI.ActionResult? {
        reads += 1
        peakReads = max(peakReads, reads)
        defer { reads -= 1 }
        if blockReads {
            do { try await stall() }
            catch {
                let delay = readCancellationDelay
                await Task.detached { try? await Task.sleep(for: delay) }.value
                throw error
            }
        }
        try await Task.sleep(for: readDelay)
        while synchronizeReads, peakReads < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        return result
    }

    func containsActionResult(for _: REAPI.Digest) async throws -> Bool { result != nil }

    func storeActionResult(_ result: REAPI.ActionResult, for _: REAPI.Digest) async throws {
        self.result = result
    }

    func uploadAvailableBlobs(_ files: [REAPI.Digest: URL]) async throws -> REAPIBlobUpload {
        var failures: [REAPI.Digest: String] = [:]
        for (digest, file) in files {
            if digest == Self.rejected { failures[digest] = "permission denied" }
            else { blobs[digest] = try Data(contentsOf: file) }
        }
        let available = Set(files.keys).subtracting(failures.keys)
        return REAPIBlobUpload(available: available, failures: failures, uploaded: knownUploads ? available : nil)
    }

    func uploadBlobs(_ files: [REAPI.Digest: URL]) async throws {
        requiredUploads += 1
        activeUploads += 1
        peakUploads = max(peakUploads, activeUploads)
        defer { activeUploads -= 1 }
        do {
            while blockUploads {
                try await Task.sleep(for: .milliseconds(5))
            }
        } catch {
            cancelledOperations += 1
            throw error
        }
        let upload = try await uploadAvailableBlobs(files)
        if !upload.failures.isEmpty { throw REAPICacheError.uploadFailed(reason: "permission denied") }
    }

    func releaseReads() { blockReads = false }

    func releaseUploads() { blockUploads = false }

    func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        guard let data = blobs[digest] else { throw REAPICacheError.corruptBlob }
        try data.write(to: path)
    }

    private func stall() async throws {
        do { try await Task.sleep(for: .seconds(60)) }
        catch {
            cancelledOperations += 1
            throw error
        }
    }
}
