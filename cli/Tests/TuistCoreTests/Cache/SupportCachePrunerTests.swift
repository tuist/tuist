import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistEnvironment
import TuistEnvironmentTesting
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
    func size_countsHiddenDescendants() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        // A plugin entry is a git checkout, and `.git` is usually the bulk of it.
        let plugin = try await seed(.plugins, name: "plugin", bytes: 1_000_000, lastUsed: Date(), in: cache)
        let git = plugin.appending(components: "Repository", ".git", "objects")
        try await fileSystem.makeDirectory(at: git)
        FileManager.default.createFile(
            atPath: git.appending(component: "pack").pathString,
            contents: Data(repeating: 0x41, count: 4_000_000)
        )

        // A measurement blind to hidden entries would report the 1 MB outside `.git` and let the
        // entry occupy five times what it is charged for. At or above, not equal: the walk counts
        // the directories it descends as well as the files under them.
        #expect(try await subject(cache).size(of: plugin) >= 5_000_000)
    }

    @Test(.inTemporaryDirectory)
    func prune_evictsHiddenBytesThatPutTheCacheOverBudget() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        let lastUsed = now.addingTimeInterval(-2 * hour)
        let plugin = try await seed(.plugins, name: "plugin", bytes: 1000, lastUsed: lastUsed, in: cache)
        let git = plugin.appending(components: "Repository", ".git")
        try await fileSystem.makeDirectory(at: git)
        FileManager.default.createFile(
            atPath: git.appending(component: "pack").pathString,
            contents: Data(repeating: 0x41, count: 4_000_000)
        )
        // Writing into the entry bumped its modification time, and an entry touched this recently
        // is one a concurrent command may be using, so restamp it as the seed left it.
        try FileManager.default.setAttributes([.modificationDate: lastUsed], ofItemAtPath: plugin.pathString)

        // Everything the entry holds outside `.git` fits the budget several times over.
        try await subject(cache).prune(maxBytes: 100_000, now: now)

        #expect(try await !fileSystem.exists(plugin))
    }

    @Test(.inTemporaryDirectory)
    func prune_doesNotCountAnEntryItFailedToRemove() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        let now = Date()
        let lastUsed = now.addingTimeInterval(-2 * hour)
        let unremovable = try await seed(.runs, name: "locked", bytes: 1_000_000, lastUsed: lastUsed, in: cache)
        let removable = try await seed(.manifests, name: "1.abc", bytes: 1_000_000, lastUsed: lastUsed, in: cache)

        // Immutable, so the eviction of the first candidate fails.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: unremovable.pathString)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: unremovable.pathString) }

        try await subject(cache).prune(maxBytes: 1_500_000, now: now)

        // Counting the failed removal would have left the cache over budget with the entry still on
        // disk, believing it had reclaimed enough.
        #expect(try await fileSystem.exists(unremovable))
        #expect(try await !fileSystem.exists(removable))
    }

    @Test(.inTemporaryDirectory)
    func size_measuresARegularFileRatherThanItsEmptyGlob() async throws {
        let cache = try #require(FileSystem.temporaryTestDirectory)
        // A manifest is cached as one flat file, not as a directory.
        let manifest = try await seed(.manifests, name: "1.abc", bytes: 1_000_000, lastUsed: Date(), in: cache)

        #expect(try await subject(cache).size(of: manifest) == 1_000_000)
    }

    @Test(.withMockedEnvironment()) func budget_splitsTheStagedBudgetWithTheModuleCache() throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CACHE_MAX_BYTES"] = "10000000"

        // The module cache holds what a build links and a miss costs a download; these hold what
        // the CLI derives along the way and a miss costs a recompute, so they take the small share.
        #expect(CacheBudget.supportCaches == 1_000_000)
        #expect(CacheBudget.moduleCache == 9_000_000)
        // The two are one budget, so bounding these cannot push the volume past what it was sized
        // for — the property the shared variable exists to keep.
        #expect(CacheBudget.supportCaches! + CacheBudget.moduleCache! == 10_000_000)
    }

    @Test(.withMockedEnvironment()) func budget_capsTheSupportShareOnALargeBudget() throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CACHE_MAX_BYTES"] = "107374182400" // 100 GiB

        // A compiled helpers module is the same size whatever the volume is, so the share is capped
        // rather than proportional and the rest stays with the module cache.
        #expect(CacheBudget.supportCaches == 1024 * 1024 * 1024)
        #expect(CacheBudget.moduleCache == 107_374_182_400 - 1024 * 1024 * 1024)
    }

    @Test(.withMockedEnvironment()) func budget_isUnboundedWithoutAStagedBudget() {
        // Off a runner the cache is the user's own directory, so only the age pass applies.
        #expect(CacheBudget.supportCaches == nil)
        #expect(CacheBudget.moduleCache == nil)
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
