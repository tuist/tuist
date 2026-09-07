import FileSystem
import FileSystemTesting
import Foundation
import HTTPTypes
import Mockable
import Testing
import TuistServer

@testable import TuistCache

struct ContentDefinedChunkingTests {
    private func corpus() -> Data {
        var state: UInt64 = 0x1234_5678
        return Data((0 ..< 8 * 1024 * 1024).map { _ in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return UInt8(truncatingIfNeeded: state)
        })
    }

    @Test(.inTemporaryDirectory)
    func boundariesMatchRustAndKotlin() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "artifact").pathString)
        let bytes = corpus()
        try bytes.write(to: url)
        let artifact = try ContentDefinedChunking.scan(url)
        #expect(artifact.chunks.map(\.digest.size) == [
            529_076, 595_136, 418_015, 222_683, 617_331, 182_609, 709_558, 568_609, 683_124,
            161_158, 704_587, 540_566, 686_652, 721_374, 550_320, 333_401, 164_409,
        ])
        #expect(artifact.digest == ContentDefinedChunking.digest(bytes))
        let changed = bytes.prefix(1_000_000) + Data("an insertion".utf8) + bytes.dropFirst(1_000_000)
        try changed.write(to: url)
        let known = Set(artifact.chunks.map(\.digest))
        let reused = try ContentDefinedChunking.scan(url).chunks.filter { known.contains($0.digest) }
            .reduce(0) { $0 + $1.digest.size }
        #expect(reused > bytes.count * 3 / 4)
    }

    @Test(.inTemporaryDirectory)
    func monolithicCompressedArchivesKeepTheLegacyUploader() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "archive.zip").pathString)
        for count in [1, 2] {
            var archive: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
            for _ in 0 ..< count {
                var header = [UInt8](repeating: 0, count: 46)
                header.replaceSubrange(0 ..< 4, with: [0x50, 0x4B, 0x01, 0x02])
                header[10] = 8
                header[22] = 8
                archive += header
            }
            var end = [UInt8](repeating: 0, count: 22)
            end.replaceSubrange(0 ..< 4, with: [0x50, 0x4B, 0x05, 0x06])
            end[10] = UInt8(count)
            end[12] = UInt8(count * 46)
            end[16] = 4
            try Data(archive + end).write(to: url)
            #expect(try ContentDefinedChunking.hasReusableArchiveEntries(url) == (count == 2))
        }
    }

    @Test(.inTemporaryDirectory)
    func unsupportedServersDoNotReceiveChunkWrites() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "artifact").pathString)
        try corpus().write(to: url)
        for status in [404, 405, 501, 200] {
            let wire = StubWire(status: status)
            let result = try await ChunkedModuleCacheUploadService().uploadIfSupported(
                fileURL: url, endpointKey: UUID().uuidString, target: [:]
            ) { operation, method, data, extra in await wire.send(operation, method, data, extra) }
            #expect(!result)
            #expect(await wire.operations == ["capabilities"])
        }
    }

    @Test(.inTemporaryDirectory)
    func mixedVersionNodeDisablesChunking() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "artifact").pathString)
        try corpus().write(to: url)
        let wire = StubWire(status: 404, capable: true)
        let endpoint = UUID().uuidString
        for _ in 0 ..< 2 {
            let result = try await ChunkedModuleCacheUploadService().uploadIfSupported(
                fileURL: url, endpointKey: endpoint, target: [:]
            ) { operation, method, data, extra in await wire.send(operation, method, data, extra) }
            #expect(!result)
        }
        #expect(await wire.operations == ["capabilities", "missing"])
    }

    @Test(.inTemporaryDirectory, .enabled(if: ProcessInfo.processInfo.environment["TUIST_CHUNKING_TEST_URL"] != nil))
    func productionUploaderRoundTripsThroughLocalKura() async throws {
        let base = try #require(ProcessInfo.processInfo.environment["TUIST_CHUNKING_TEST_URL"])
        #expect(base.hasPrefix("http://127.0.0.1:"))
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let url = URL(fileURLWithPath: directory.appending(component: "artifact").pathString)
        let project = "swift-chunks-\(UUID().uuidString)"
        let wire = LocalWire(base: base, project: project)
        let original = corpus()
        let changed = original.prefix(1_000_000) + Data("an insertion".utf8) + original.dropFirst(1_000_000)
        let fixturePaths = ProcessInfo.processInfo.environment["TUIST_CHUNKING_MODULES"]?.split(separator: ":") ?? []
        let fixtures = try fixturePaths.map { try Data(contentsOf: URL(fileURLWithPath: String($0))) }
        for path in fixturePaths {
            #expect(try !ContentDefinedChunking.hasReusableArchiveEntries(URL(fileURLWithPath: String(path))))
        }
        for (index, bytes) in ([original, changed] + fixtures).enumerated() {
            try bytes.write(to: url)
            let before = await wire.uploadedBytes
            let started = Date()
            let uploaded = try await ChunkedModuleCacheUploadService().uploadIfSupported(
                fileURL: url, endpointKey: project,
                target: ["hash": "artifact-\(index)", "name": "Framework", "cache_category": "builds"]
            ) { operation, method, data, extra in
                try await wire.send(operation, method: method, data: data, extra: extra)
            }
            #expect(uploaded)
            let sent = await wire.uploadedBytes - before
            print(
                "BENCH module phase=\(index) whole_bytes=\(bytes.count) uploaded_bytes=\(sent) elapsed_ms=\(Date().timeIntervalSince(started) * 1000)"
            )
            if index == 1 { #expect(sent < bytes.count / 2) }
            let legacyURL =
                try #require(
                    URL(
                        string: "\(base)/api/cache/module/artifact-\(index)?account_handle=chunking-test&project_handle=\(project)&hash=artifact-\(index)&name=Framework&cache_category=builds"
                    )
                )
            let (restored, response) = try await URLSession.shared.data(from: legacyURL)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(restored == bytes)
        }
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any).willReturn(.project("local-test-token"))
        let tokens = MockCacheTokenStoring()
        given(tokens).cacheToken(authenticationURL: .any, fullHandle: .any).willReturn(nil)
        try original.write(to: url)
        let uploaded = try await ChunkedModuleCacheUploadService(cacheTokenStore: tokens).uploadIfSupported(
            artifactPath: directory.appending(component: "artifact"), accountHandle: "chunking-test", projectHandle: project,
            hash: "production-transport", name: "Framework", cacheCategory: "builds",
            serverURL: try #require(URL(string: base)), authenticationURL: try #require(URL(string: base)),
            serverAuthenticationController: authentication
        )
        #expect(uploaded)
        let legacyURL =
            try #require(
                URL(
                    string: "\(base)/api/cache/module/production-transport?account_handle=chunking-test&project_handle=\(project)&hash=production-transport&name=Framework&cache_category=builds"
                )
            )
        let (restored, response) = try await URLSession.shared.data(from: legacyURL)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(restored == original)
    }

    private actor StubWire {
        let status: Int
        let capable: Bool
        var operations: [String] = []

        init(status: Int, capable: Bool = false) { self.status = status; self.capable = capable }

        func send(_ operation: String, _: HTTPRequest.Method, _: Data?, _: [String: String]) -> (Int, Data) {
            operations.append(operation)
            if operation == "capabilities", capable {
                return (
                    200,
                    Data(
                        #"{"version":1,"algorithm":"fastcdc2020","average_chunk_bytes":524288,"seed":0,"normalization":2,"minimum_blob_bytes":2097152,"maximum_chunk_bytes":2097152,"maximum_chunks":16384}"#
                            .utf8
                    )
                )
            }
            return (status, Data("{}".utf8))
        }
    }

    private actor LocalWire {
        let base: String
        let project: String
        var uploadedBytes = 0

        init(base: String, project: String) { self.base = base; self.project = project }

        func send(
            _ operation: String,
            method: HTTPRequest.Method,
            data: Data?,
            extra: [String: String]
        ) async throws -> (Int, Data) {
            var components = try #require(URLComponents(string: "\(base)/api/cache/chunks/\(operation)"))
            components
                .queryItems = (["account_handle": "chunking-test", "project_handle": project, "kind": "module"]
                    .merging(extra) { _, new in new })
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = URLRequest(url: try #require(components.url))
            request.httpMethod = method.rawValue
            request.httpBody = data
            request.setValue(
                operation == "upload" ? "application/octet-stream" : "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            if operation == "upload" { uploadedBytes += data?.count ?? 0 }
            let (bytes, response) = try await URLSession.shared.data(for: request)
            return (try #require(response as? HTTPURLResponse).statusCode, bytes)
        }
    }
}
