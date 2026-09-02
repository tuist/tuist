import FileSystem
import Foundation
import Path

/// Bounds the growth of every cache category that is not the binary cache and not the compilation
/// CAS.
///
/// Those two are budgeted where they are written, by `TUIST_CACHE_MAX_BYTES` and
/// `COMPILATION_CACHE_LIMIT_SIZE`. Everything else the CLI caches — result bundles, compiled
/// helper modules, manifests, plugin checkouts — had no budget at all, so on a runner's fixed-size
/// cache volume it grew until the volume hit ENOSPC and every command died at its first cache
/// write. It now takes `CacheBudget.supportCaches`, the module cache's own budget less the share
/// carved off it, so bounding these cannot push the volume past what the host sized it for.
///
/// Retention runs in two passes, on different schedules because they cost very different amounts.
/// The per-category age pass drops what is no longer in use, costs one stat per entry, and runs on
/// every command everywhere, including on developer machines where there is no volume to fill. The
/// byte pass arbitrates what the age pass left, runs only where a budget is staged, and has to
/// measure each surviving entry's whole tree — against a warm runner cache that is ~0.3s where the
/// age pass is ~0.02s, most of it in a plugin's git checkout. It is also arbitrating growth that
/// accrues across runs rather than within one, so it sweeps periodically instead of charging every
/// command for a measurement whose answer barely moves between them.
///
/// The budget bounds the cache at the start of a command rather than admitting each write against
/// it, which for these categories is a bound and not merely a prune: a command adds at most one
/// entry to each of them (one result bundle, one compiled helpers module, one manifest per manifest
/// file), so what a command can add on top of a pruned cache is bounded by the run itself and fits
/// the image's reserve. That is the difference from the binary cache, where a single `tuist cache`
/// writes hundreds of artifacts in one command and the budget has to gate the writes themselves.
public struct SupportCachePruner {
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let fileSystem: FileSysteming

    /// Entries touched more recently than this are never evicted by the byte pass. A concurrent
    /// `tuist` process sharing the cache directory refreshes an entry when it resolves it, so the
    /// window is what keeps this process from reclaiming a path that one is building against.
    private static let evictionGracePeriod: TimeInterval = 60 * 60

    /// How often the byte pass sweeps. Between sweeps the age pass is the only bound, which holds
    /// because a command adds at most one entry to each category, so what accrues in a window is
    /// bounded by the commands in it and fits the image's reserve.
    private static let byteSweepInterval: TimeInterval = 15 * 60

    /// Records when the byte pass last swept, beside the category directories rather than inside
    /// one, so it is not an entry any category has to account for and does not reach the cache
    /// inventory a runner promotes on.
    private static let sweepStampName = ".support-cache-sweep"

    public init(
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.fileSystem = fileSystem
    }

    /// Unset outside a runner, where the cache is the user's own directory and only the
    /// per-category retention applies.
    var budget: Int? { CacheBudget.supportCaches }

    public func prune() async throws {
        try await prune(maxBytes: budget, now: Date())
    }

    func prune(maxBytes: Int?, now: Date) async throws {
        var survivors: [Entry] = []
        for category in CacheCategory.supportCaches {
            guard case let .support(maxAge) = category.budget else { continue }
            survivors += try await expire(category, olderThan: now.addingTimeInterval(-maxAge))
        }
        guard let maxBytes, await claimByteSweep(now: now) else { return }
        try await evict(survivors, toFit: maxBytes, notModifiedAfter: now.addingTimeInterval(-Self.evictionGracePeriod))
    }

    /// Whether the byte sweep is due, claiming it when it is. Best effort in both directions: a
    /// cache directory that cannot hold the stamp sweeps on every command rather than on none.
    private func claimByteSweep(now: Date) async -> Bool {
        let stamp = cacheDirectoriesProvider.cacheDirectory().appending(component: Self.sweepStampName)
        if let metadata = try? await fileSystem.fileMetadata(at: stamp),
           now.timeIntervalSince(metadata.lastModificationDate) < Self.byteSweepInterval
        {
            return false
        }
        try? await fileSystem.touch(stamp)
        try? await fileSystem.setFileTimes(of: stamp, lastAccessDate: nil, lastModificationDate: now)
        return true
    }

    /// Removes the category's entries last used before `cutoff` and returns the ones that survived.
    private func expire(_ category: CacheCategory, olderThan cutoff: Date) async throws -> [Entry] {
        let directory = try cacheDirectoriesProvider.cacheDirectory(for: category)
        guard try await fileSystem.exists(directory) else { return [] }

        var survivors: [Entry] = []
        for path in try await fileSystem.glob(directory: directory, include: ["*"]).collect() {
            guard let metadata = try await fileSystem.fileMetadata(at: path) else { continue }
            if metadata.lastModificationDate < cutoff {
                try? await fileSystem.remove(path)
            } else {
                survivors.append(
                    Entry(path: path, category: category, lastUsed: metadata.lastModificationDate)
                )
            }
        }
        return survivors
    }

    /// Evicts entries until what is left fits `maxBytes`, cheapest to lose first and
    /// least-recently-used within a category.
    private func evict(_ entries: [Entry], toFit maxBytes: Int, notModifiedAfter: Date) async throws {
        var sized: [(entry: Entry, size: Int)] = []
        var used = 0
        for entry in entries {
            let size = try await size(of: entry.path)
            used += size
            sized.append((entry, size))
        }
        guard used > maxBytes else { return }

        let candidates = sized
            .filter { $0.entry.lastUsed <= notModifiedAfter }
            .sorted {
                let (left, right) = (Self.evictionRank($0.entry.category), Self.evictionRank($1.entry.category))
                return left == right ? $0.entry.lastUsed < $1.entry.lastUsed : left < right
            }

        for candidate in candidates where used > maxBytes {
            do {
                try await fileSystem.remove(candidate.entry.path)
            } catch {
                // A concurrent `tuist` may have removed the entry first, in which case its bytes
                // are reclaimed all the same. Anything else — a permission error, a busy file —
                // leaves the entry on disk, and counting it would stop the loop believing it had
                // reached the budget while the cache is still over it.
                guard (try? await fileSystem.exists(candidate.entry.path)) == false else { continue }
            }
            used -= candidate.size
        }
    }

    /// On-disk size of a cache entry. Entries are directories in most categories, but a manifest is
    /// cached as a single file, so a file has to measure as itself rather than as the empty glob of
    /// its descendants.
    ///
    /// The glob descends into hidden entries, which a plugin's `.git` checkout depends on
    /// (`FileSystem.glob` searches with `skipHiddenFiles: false`), and counts the directories it
    /// walks as well as their files, so an entry measures at or above what it occupies.
    func size(of path: AbsolutePath) async throws -> Int {
        guard try await fileSystem.exists(path, isDirectory: true) else {
            guard let metadata = try await fileSystem.fileMetadata(at: path) else { return 0 }
            return Int(metadata.size)
        }
        var total = 0
        for file in try await fileSystem.glob(directory: path, include: ["**/*"]).collect() {
            if let metadata = try await fileSystem.fileMetadata(at: file) {
                total += Int(metadata.size)
            }
        }
        return total
    }

    /// Position in the eviction order. A category outside it is evicted last rather than first, so
    /// one added without a place in the order cannot start losing entries by omission.
    private static func evictionRank(_ category: CacheCategory) -> Int {
        CacheCategory.supportCaches.firstIndex(of: category) ?? CacheCategory.supportCaches.count
    }

    private struct Entry {
        let path: AbsolutePath
        let category: CacheCategory
        let lastUsed: Date
    }
}

extension FileSysteming {
    /// Records that a support-cache entry was used, so `SupportCachePruner` reads it as recently
    /// used rather than as old as the run that first wrote it.
    ///
    /// These caches are content-addressed: a hit reads the entry, or does not even read it and only
    /// checks that it exists. Without this, an entry used by every single command still ages out of
    /// its retention window, and the byte pass evicts exactly the entries that are worth keeping.
    public func markCacheEntryUsed(at path: AbsolutePath) async {
        try? await setFileTimes(of: path, lastAccessDate: nil, lastModificationDate: Date())
    }
}
