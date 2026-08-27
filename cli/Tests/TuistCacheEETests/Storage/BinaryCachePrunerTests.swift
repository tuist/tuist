import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting

@testable import TuistCacheEE
@testable import TuistTesting

struct BinaryCachePrunerTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func pruneToBudget_evictsEntriesToMakeRoomForIncomingArtifacts() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let binariesDirectory = try await seedEntries(count: 3, in: temporaryDirectory)

        let incoming = temporaryDirectory.appending(component: "incoming")
        try await fileSystem.makeDirectory(at: incoming)
        FileManager.default.createFile(
            atPath: incoming.appending(component: "binary").pathString,
            contents: Data(repeating: 0x41, count: 1_000_000)
        )

        // When: a budget that holds ~2 entries, one of which the incoming artifact claims.
        try await subject(binariesDirectory: binariesDirectory)
            .clean(maxBytes: 2_500_000 - 1_000_000, minimumEntries: 0)

        // Then
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.count == 1)
        #expect(try await fileSystem.exists(binariesDirectory.appending(component: "hash0")))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func pruneToBudget_evictsEveryEntryWhenTheIncomingArtifactsNeedTheWholeBudget() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CACHE_MAX_BYTES"] = "2500000"
        let binariesDirectory = try await seedEntries(count: 1, in: temporaryDirectory)

        let incoming = temporaryDirectory.appending(component: "incoming")
        try await fileSystem.makeDirectory(at: incoming)
        FileManager.default.createFile(
            atPath: incoming.appending(component: "binary").pathString,
            contents: Data(repeating: 0x41, count: 2_000_000)
        )

        // When: the incoming artifact claims all but 0.5 MB of the budget, which the
        // cached 1 MB entry does not fit into.
        try await subject(binariesDirectory: binariesDirectory).pruneToBudget(makingRoomFor: [incoming])

        // Then
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.isEmpty)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func pruneToBudget_keepsTheMostRecentlyUsedEntryWhenItAloneExceedsTheBudget() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CACHE_MAX_BYTES"] = "100"
        let binariesDirectory = try await seedEntries(count: 1, in: temporaryDirectory)

        // When
        try await subject(binariesDirectory: binariesDirectory).pruneToBudget()

        // Then: dropping it would only force a full re-pull on the next generate.
        #expect(try await fileSystem.exists(binariesDirectory.appending(component: "hash0")))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func pruneToBudget_isANoOpWithoutABudget() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let binariesDirectory = try await seedEntries(count: 3, in: temporaryDirectory)

        // When
        try await subject(binariesDirectory: binariesDirectory).pruneToBudget()

        // Then
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.count == 3)
    }

    /// `count` ~1 MB entries, staggered so entry 0 is the most recently used.
    private func seedEntries(count: Int, in temporaryDirectory: AbsolutePath) async throws -> AbsolutePath {
        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)
        for index in 0 ..< count {
            let entry = binariesDirectory.appending(component: "hash\(index)")
            let artifact = entry.appending(component: "framework.xcframework")
            try await fileSystem.makeDirectory(at: artifact)
            FileManager.default.createFile(
                atPath: artifact.appending(component: "binary").pathString,
                contents: Data(repeating: 0x41, count: 1_000_000)
            )
            let date = Calendar.current.date(byAdding: .hour, value: -index, to: Date())!
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: entry.pathString)
        }
        return binariesDirectory
    }

    private func subject(binariesDirectory: AbsolutePath) -> BinaryCachePruner {
        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)
        return BinaryCachePruner(cacheDirectoriesProvider: cacheDirectoriesProvider, fileSystem: fileSystem)
    }
}
