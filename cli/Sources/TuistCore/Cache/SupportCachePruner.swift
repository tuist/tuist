import FileSystem
import Foundation
import Path
import TuistEnvironment

/// Bounds the growth of every cache category that is not the binary cache and not the compilation
/// CAS.
///
/// Those two are budgeted where they are written, by `TUIST_CACHE_MAX_BYTES` and
/// `COMPILATION_CACHE_LIMIT_SIZE`. Everything else the CLI caches — result bundles, compiled
/// helper modules, manifests, plugin checkouts — had no budget at all, so on a runner's fixed-size
/// cache volume it grew until the volume hit ENOSPC and every command died at its first cache
/// write. `TUIST_SUPPORT_CACHE_MAX_BYTES` is the third share of the same host-side split, so the
/// three budgets together cannot over-commit the image.
///
/// Retention runs in two passes. The per-category age pass drops what is no longer in use and runs
/// everywhere, including on developer machines where there is no volume to fill. The byte pass
/// arbitrates what is left, and only where a budget is staged.
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

    public init(
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.fileSystem = fileSystem
    }

    /// Unset outside a runner, where the cache is the user's own directory and only the
    /// per-category retention applies.
    var budget: Int? {
        Environment.current.variables["TUIST_SUPPORT_CACHE_MAX_BYTES"].flatMap { Int($0) }
    }

    public func prune() async throws {
        try await prune(maxBytes: budget, now: Date())
    }

    func prune(maxBytes: Int?, now: Date) async throws {
        var survivors: [Entry] = []
        for category in CacheCategory.supportCaches {
            guard case let .support(maxAge) = category.budget else { continue }
            survivors += try await expire(category, olderThan: now.addingTimeInterval(-maxAge))
        }
        guard let maxBytes else { return }
        try await evict(survivors, toFit: maxBytes, notModifiedAfter: now.addingTimeInterval(-Self.evictionGracePeriod))
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
            try? await fileSystem.remove(candidate.entry.path)
            used -= candidate.size
        }
    }

    /// On-disk size of a cache entry. Entries are directories in most categories, but a manifest is
    /// cached as a single file, so a file has to measure as itself rather than as the empty glob of
    /// its descendants.
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
