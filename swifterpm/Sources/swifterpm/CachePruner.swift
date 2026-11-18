import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Bounds the shared cache the way Tuist bounds its module cache: an entry's modification time
/// is its last use (`Cache.markUsed`), entries unused for `maxAge` are dropped after every
/// successful installation, and where a byte budget is set the least recently used entries are
/// evicted until the cache fits it.
///
/// Restores link entries into checkouts, so an entry can only go while nothing is linking it:
/// eviction takes the entry's lock exclusively without waiting, skips the entry when a restore
/// holds it, and re-reads its last use under the lock. A checkout that still links an evicted
/// entry reads it as a miss on its next installation.
///
/// Only SwifterPM's own layout is pruned. Native SwiftPM's directories in the same root
/// (`repositories`, `registry/downloads`, `prebuilts`, `manifests` and the files at the top of
/// `artifacts`) are locked under SwiftPM's own scheme, and lock files must never be unlinked.
enum CachePruner {
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    /// Entries used more recently than this are never evicted by the byte budget. Every entry
    /// the installation that just ran used is inside it, as is every entry a concurrent one has
    /// just resolved.
    static let evictionGracePeriod: TimeInterval = 60 * 60

    struct Entry: Equatable {
        let url: URL
        /// The `Cache.lock` namespace its publishers and restores take, if any.
        let lockNamespace: String?
        let lastUsed: Date
        let isDirectory: Bool
        /// Temporary directories an interrupted publication left behind expire by age only.
        let evictableByBudget: Bool
    }

    /// Prunes after a successful installation. Failures are warnings: cache maintenance never
    /// fails the installation it follows. Cancellation still propagates.
    static func pruneAfterInstallation(cacheDirectory: URL?, maxBytes: Int?) async throws {
        do {
            try await prune(root: try Cache.resolvedRoot(cacheDirectory), maxBytes: maxBytes, now: Date())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Environment.warningHandler?("could not prune the SwifterPM cache: \(error)")
        }
    }

    static func prune(root: URL, maxBytes: Int?, now: Date) async throws {
        try Task.checkCancellation()
        // Evicted directories are renamed into the trash, one operation each, and deleted by a
        // detached process afterwards, as restores do with the trees they replace.
        let trash = ScratchTrash(scratchDir: root)
        do {
            var survivors: [Entry] = []
            let cutoff = now.addingTimeInterval(-maxAge)
            for entry in try await entries(root: root) {
                try Task.checkCancellation()
                if entry.lastUsed < cutoff, await evict(entry, root: root, ifNotUsedAfter: cutoff, trash: trash) {
                    continue
                }
                survivors.append(entry)
            }
            if let maxBytes {
                try await evict(
                    survivors.filter(\.evictableByBudget),
                    root: root,
                    toFit: maxBytes,
                    notUsedAfter: now.addingTimeInterval(-evictionGracePeriod),
                    trash: trash
                )
            }
        } catch {
            await trash.purge()
            throw error
        }
        await trash.purge()
    }

    /// The cache's entries, one level below each SwifterPM category. Hidden names are lock
    /// files, size records and the trash, except the `.tmp-` directories of publications.
    static func entries(root: URL) async throws -> [Entry] {
        var entries: [Entry] = []
        for (category, namespace) in [("sources", "sources"), ("artifacts", "artifacts")] {
            let directory = root.appendingPathComponent(category)
            for group in try await names(in: directory) where !group.hasPrefix(".") {
                let groupDirectory = directory.appendingPathComponent(group)
                // Native SwiftPM keeps its binary artifact cache as files in `artifacts`.
                guard fileSystem.isDirectoryAndNotSymlink(groupDirectory) else { continue }
                for name in try await names(in: groupDirectory) {
                    let temporary = name.hasPrefix(".tmp-")
                    guard temporary || !name.hasPrefix(".") else { continue }
                    if let entry = await entry(
                        groupDirectory.appendingPathComponent(name),
                        lockNamespace: temporary ? nil : namespace,
                        evictableByBudget: !temporary
                    ) {
                        entries.append(entry)
                    }
                }
            }
        }
        let flat: [(String, (String) -> String?)] = [
            ("archives", { $0.hasPrefix("artifact-") ? "artifact-archives" : "archives" }),
            ("registry/archives", { _ in "registry-archives" }),
            ("manifest-dumps", { _ in nil }),
            ("metadata/remotes", { _ in nil }),
            ("validations", { _ in nil }),
        ]
        for (category, namespace) in flat {
            let directory = root.appendingPathComponent(category)
            for name in try await names(in: directory) where !name.hasPrefix(".") {
                if let entry = await entry(
                    directory.appendingPathComponent(name), lockNamespace: namespace(name), evictableByBudget: true
                ) {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    private static func names(in directory: URL) async throws -> [String] {
        guard fileSystem.isDirectoryAndNotSymlink(directory) else { return [] }
        return try await fileSystem.contentsOfDirectory(at: directory).map(\.lastPathComponent)
    }

    private static func entry(_ url: URL, lockNamespace: String?, evictableByBudget: Bool) async -> Entry? {
        // An entry that cannot be read is left where it is rather than failing every later prune.
        guard fileSystem.existsIncludingSymlinks(url),
              let modified = try? await fileSystem.fileMetadata(at: url.absolutePath)?.lastModificationDate
        else { return nil }
        return Entry(
            url: url,
            lockNamespace: lockNamespace,
            lastUsed: modified,
            isDirectory: fileSystem.isDirectoryAndNotSymlink(url),
            evictableByBudget: evictableByBudget
        )
    }

    /// Moves `entry` into the trash unless a restore holds it or used it after `cutoff`.
    private static func evict(_ entry: Entry, root: URL, ifNotUsedAfter cutoff: Date, trash: ScratchTrash) async -> Bool {
        var lock: PathLock?
        if let namespace = entry.lockNamespace {
            guard let acquired = try? await PathLock.tryAcquire(
                at: Cache.lockPath(root: root, namespace: namespace, key: entry.url.path)
            ) else { return false }
            lock = acquired
        }
        defer { withExtendedLifetime(lock) {} }
        guard let modified = try? await fileSystem.fileMetadata(at: entry.url.absolutePath)?.lastModificationDate,
              modified <= cutoff
        else { return false }
        try? await trash.discard(entry.url)
        try? await fileSystem.removePath(sizeRecord(for: entry.url))
        return !fileSystem.existsIncludingSymlinks(entry.url)
    }

    /// Evicts least recently used entries until the rest fit `maxBytes`. The most recently used
    /// entry stays even when it alone exceeds the budget, and so does anything used after
    /// `notUsedAfter`; a cache that still exceeds the budget is reported.
    private static func evict(
        _ entries: [Entry],
        root: URL,
        toFit maxBytes: Int,
        notUsedAfter: Date,
        trash: ScratchTrash
    ) async throws {
        let sizes = try await sizes(of: entries)
        var used = sizes.values.reduce(0, +)
        guard used > maxBytes else { return }
        let newest = entries.max { $0.lastUsed < $1.lastUsed }
        let candidates = entries
            .filter { $0.lastUsed <= notUsedAfter && $0 != newest }
            .sorted { $0.lastUsed < $1.lastUsed }
        for candidate in candidates where used > maxBytes {
            try Task.checkCancellation()
            if await evict(candidate, root: root, ifNotUsedAfter: notUsedAfter, trash: trash) {
                used -= sizes[candidate.url] ?? 0
            }
        }
        if used > maxBytes {
            Environment.warningHandler?(
                "the SwifterPM cache at \(root.path) holds \(gigabytes(used)) in entries in use, "
                    + "more than its \(gigabytes(maxBytes)) budget; give it more space"
            )
        }
    }

    private static func gigabytes(_ bytes: Int) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    /// Sizes in bytes. Entries are immutable, so a directory is measured once and its size is
    /// recorded beside it, keyed by its inode so a republished entry is measured again.
    static func sizes(of entries: [Entry]) async throws -> [URL: Int] {
        var sizes: [URL: Int] = [:]
        var unmeasured: [(entry: Entry, inode: UInt64)] = []
        for entry in entries {
            guard let status = status(entry.url) else { continue }
            guard entry.isDirectory else {
                sizes[entry.url] = Int(status.st_size)
                continue
            }
            let inode = UInt64(status.st_ino)
            if let data = try? await fileSystem.readFile(at: sizeRecord(for: entry.url).absolutePath) {
                let fields = String(decoding: data, as: UTF8.self).split(separator: " ").map(String.init)
                if fields.count == 2, UInt64(fields[0], radix: 10) == inode, let size = Int(fields[1], radix: 10) {
                    sizes[entry.url] = size
                    continue
                }
            }
            unmeasured.append((entry, inode))
        }
        for batch in stride(from: 0, to: unmeasured.count, by: 128).map({
            Array(unmeasured[$0 ..< min($0 + 128, unmeasured.count)])
        }) {
            let measured = try await diskUsage(batch.map(\.entry.url))
            for (entry, inode) in batch {
                guard let size = measured[entry.url.path] else { continue }
                sizes[entry.url] = size
                try? await fileSystem.atomicWrite("\(inode) \(size)", to: sizeRecord(for: entry.url))
            }
        }
        return sizes
    }

    private static func diskUsage(_ urls: [URL]) async throws -> [String: Int] {
        // A path that went away meanwhile fails the batch; its entries are measured next time.
        guard let result = try? await SystemProcess.run("/usr/bin/du", ["-sk", "--"] + urls.map(\.path)) else {
            return [:]
        }
        var sizes: [String: Int] = [:]
        for line in String(decoding: result.stdout, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
            if fields.count == 2, let kilobytes = Int(fields[0]) {
                sizes[fields[1]] = kilobytes * 1024
            }
        }
        return sizes
    }

    private static func status(_ url: URL) -> stat? {
        var status = stat()
        return lstat(url.path, &status) == 0 ? status : nil
    }

    static func sizeRecord(for entry: URL) -> URL {
        entry.deletingLastPathComponent().appendingPathComponent(".\(entry.lastPathComponent).size")
    }
}
