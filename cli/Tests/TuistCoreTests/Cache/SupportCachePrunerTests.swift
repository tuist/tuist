import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
@testable import TuistCore

struct SupportCachePrunerTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func prune_dropsEntriesPastTheirCategoryRetention() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        // A result bundle from a run whose process died before the upload could remove it.
        let staleRun = try await seed(.runs, name: "run", bytes: 1_000_000, lastUsed: now.addingTimeInterval(-2 * day), in: cache)
        let freshRun = try await seed(
            .runs,
            name: "fresh",
            bytes: 1_000_000,
            lastUsed: now.addingTimeInterval(-1 * hour),
            in: cache
        )
        // Well past the runs window, but nowhere near the plugin one.
        let plugin = try await seed(
            .plugins,
            name: "plugin",
            bytes: 1_000_000,
            lastUsed: now.addingTimeInterval(-7 * day),
            in: cache
        )

        try await subject(cache).prune(maxBytes: nil, now: now)

        #expect(try await !fileSystem.exists(staleRun))
        #expect(try await fileSystem.exists(freshRun))
        #expect(try await fileSystem.exists(plugin))
    }

    @Test(.inTemporaryDirectory)
    func prune_isANoOpWithoutABudgetOnceNothingHasExpired() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        let helpers = try await seed(
            .projectDescriptionHelpers, name: "hash", bytes: 5_000_000, lastUsed: now.addingTimeInterval(-2 * day), in: cache
        )

        // A developer machine has no volume to fill, so the byte budget is unset.
        try await subject(cache).prune(maxBytes: nil, now: now)

        #expect(try await fileSystem.exists(helpers))
    }

    @Test(.inTemporaryDirectory)
    func prune_evictsWhatCostsLeastToLoseFirst() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        // The plugin is the LEAST recently used of the three, so plain recency would reach it first.
        let run = try await seed(.runs, name: "run", bytes: 1_000_000, lastUsed: now.addingTimeInterval(-2 * hour), in: cache)
        let manifest = try await seed(
            .manifests, name: "1.abc", bytes: 1_000_000, lastUsed: now.addingTimeInterval(-3 * hour), in: cache
        )
        let plugin = try await seed(
            .plugins, name: "plugin", bytes: 1_000_000, lastUsed: now.addingTimeInterval(-6 * day), in: cache
        )

        // A budget that holds one of the three entries.
        try await subject(cache).prune(maxBytes: 1_500_000, now: now)

        // A plugin is refetched over the network, a manifest is reloaded, a run bundle is gone
        // either way, so eviction reaches them in that order however recently each was used.
        #expect(try await !fileSystem.exists(run))
        #expect(try await !fileSystem.exists(manifest))
        #expect(try await fileSystem.exists(plugin))
    }

    @Test(.inTemporaryDirectory)
    func prune_evictsTheLeastRecentlyUsedEntryOfACategoryFirst() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        let cold = try await seed(
            .projectDescriptionHelpers, name: "cold", bytes: 1_000_000, lastUsed: now.addingTimeInterval(-6 * day), in: cache
        )
        let warm = try await seed(
            .projectDescriptionHelpers, name: "warm", bytes: 1_000_000, lastUsed: now.addingTimeInterval(-2 * hour), in: cache
        )

        try await subject(cache).prune(maxBytes: 1_500_000, now: now)

        #expect(try await !fileSystem.exists(cold))
        #expect(try await fileSystem.exists(warm))
    }

    @Test(.inTemporaryDirectory)
    func prune_neverEvictsAnEntryAConcurrentCommandMayHaveJustResolved() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        // Compiled moments ago by a sibling `tuist` sharing this cache directory, which is about to
        // hand the module to swiftc.
        let inFlight = try await seed(
            .projectDescriptionHelpers, name: "hash", bytes: 5_000_000, lastUsed: now.addingTimeInterval(-1 * 60), in: cache
        )

        try await subject(cache).prune(maxBytes: 1, now: now)

        #expect(try await fileSystem.exists(inFlight))
    }

    @Test(.inTemporaryDirectory)
    func prune_leavesTheBinaryCacheToItsOwnBudget() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        let binary = try await seed(
            .binaries, name: "hash", bytes: 5_000_000, lastUsed: now.addingTimeInterval(-365 * day), in: cache
        )

        try await subject(cache).prune(maxBytes: 1, now: now)

        #expect(try await fileSystem.exists(binary))
    }

    @Test(.inTemporaryDirectory)
    func size_measuresARegularFileRatherThanItsEmptyGlob() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        // A manifest is cached as one flat file, not as a directory.
        let manifest = try await seed(.manifests, name: "1.abc", bytes: 1_000_000, lastUsed: Date(), in: cache)

        #expect(try await subject(cache).size(of: manifest) == 1_000_000)
    }

    @Test func everyCategoryNamesTheBudgetThatBoundsIt() {
        let budgeted = Set(CacheCategory.supportCaches + [.binaries])

        #expect(budgeted == Set(CacheCategory.allCases))
    }

    private let day: TimeInterval = 60 * 60 * 24
    private let hour: TimeInterval = 60 * 60

    /// Seeds one `bytes`-sized entry in `category`, last used at `lastUsed`. Manifests are cached as
    /// flat files and everything else as directories, so the layout follows the category.
    private func seed(
        _ category: CacheCategory,
        name: String,
        bytes: Int,
        lastUsed: Date,
        in cache: AbsolutePath
    ) async throws -> AbsolutePath {
        let directory = cache.appending(component: category.directoryName)
        if try await !fileSystem.exists(directory) {
            try await fileSystem.makeDirectory(at: directory)
        }
        let entry = directory.appending(component: name)
        switch category {
        case .manifests:
            FileManager.default.createFile(atPath: entry.pathString, contents: Data(repeating: 0x41, count: bytes))
        default:
            try await fileSystem.makeDirectory(at: entry)
            FileManager.default.createFile(
                atPath: entry.appending(component: "content").pathString,
                contents: Data(repeating: 0x41, count: bytes)
            )
        }
        try FileManager.default.setAttributes([.modificationDate: lastUsed], ofItemAtPath: entry.pathString)
        return entry
    }

    private func subject(_ cache: AbsolutePath) -> SupportCachePruner {
        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        for category in CacheCategory.allCases {
            given(cacheDirectoriesProvider)
                .cacheDirectory(for: .value(category))
                .willReturn(cache.appending(component: category.directoryName))
        }
        return SupportCachePruner(cacheDirectoriesProvider: cacheDirectoriesProvider, fileSystem: fileSystem)
    }
}
