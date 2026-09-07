import FileSystem
import FileSystemTesting
import Foundation
import HTTPTypes
import Testing

@testable import TuistCache

struct ChunkedModuleCacheDownloadTests {
    @Test(.inTemporaryDirectory)
    func freshClientReusesDiskChunksAndRepairsCorruption() async throws {
        let directory = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let endpoint = UUID().uuidString
        let wire = Wire(mode: .available)
        for _ in 0 ..< 2 {
            let downloaded = try await ChunkedModuleCacheDownloadService(directory: directory).downloadIfSupported(
                endpointKey: endpoint,
                target: [:]
            ) {
                operation, _, _, _ in try await wire.send(operation)
            }
            #expect(downloaded == Data([1, 2, 3]))
        }
        #expect(await wire.downloads == 1)
        let cache = LocalChunkCache(directory: directory, scope: endpoint)
        try Data([9, 9, 9]).write(to: cache.path(for: ContentDefinedChunking.digest(Data([1, 2, 3]))))
        let repaired = try await ChunkedModuleCacheDownloadService(directory: directory).downloadIfSupported(
            endpointKey: endpoint,
            target: [:]
        ) {
            operation, _, _, _ in try await wire.send(operation)
        }
        #expect(repaired == Data([1, 2, 3]))
        #expect(await wire.downloads == 2)
    }

    @Test(.inTemporaryDirectory, arguments: [Mode.old, .uploadOnly, .invalidSize, .corrupt, .missing, .invalidWhole, .mixed])
    func optionalFailuresRequestLegacyDownload(_ mode: Mode) async throws {
        let directory = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let wire = Wire(mode: mode)
        let downloaded = try await ChunkedModuleCacheDownloadService(directory: directory).downloadIfSupported(
            endpointKey: UUID().uuidString,
            target: [:]
        ) {
            operation, _, _, _ in try await wire.send(operation)
        }
        #expect(downloaded == nil)
        if mode == .old || mode == .uploadOnly { #expect(await wire.operations == ["capabilities"]) }
    }

    @Test(.inTemporaryDirectory)
    func oversizedSlotDoesNotAllocateOrReturnItsBytes() throws {
        let directory = URL(fileURLWithPath: try #require(FileSystem.temporaryTestDirectory).pathString)
        let cache = LocalChunkCache(directory: directory, scope: "endpoint/project")
        let digest = ContentDefinedChunking.digest(Data([1, 2, 3]))
        try Data(repeating: 1, count: 2 * 1024 * 1024 + 1).write(to: cache.path(for: digest))
        #expect(cache.get(digest) == nil)
    }

    enum Mode: Sendable { case available, old, uploadOnly, invalidSize, corrupt, missing, invalidWhole, mixed }

    private actor Wire {
        let mode: Mode
        var operations: [String] = []
        var downloads = 0

        init(mode: Mode) { self.mode = mode }

        func send(_ operation: String) throws -> (Int, Data) {
            operations.append(operation)
            let digest = ContentDefinedChunking.digest(Data([1, 2, 3]))
            if operation == "capabilities" {
                if mode == .old { return (404, Data()) }
                return (200, try JSONSerialization.data(withJSONObject: [
                    "version": 1, "download_version": mode == .uploadOnly ? 0 : 1,
                    "algorithm": "fastcdc2020", "average_chunk_bytes": 524_288, "seed": 0, "normalization": 2,
                    "minimum_blob_bytes": 2_097_152, "maximum_chunk_bytes": 2_097_152, "maximum_chunks": 16384,
                ]))
            }
            if operation == "manifest" {
                if mode == .mixed { return (501, Data()) }
                return (200, try JSONSerialization.data(withJSONObject: [
                    "blob": ["hash": mode == .invalidWhole ? String(repeating: "0", count: 64) : digest.hash, "size": 3],
                    "chunks": [["hash": digest.hash, "size": mode == .invalidSize ? -1 : 3]],
                ]))
            }
            downloads += 1
            if mode == .missing { return (404, Data()) }
            return (200, mode == .corrupt ? Data([9, 9, 9]) : Data([1, 2, 3]))
        }
    }
}
