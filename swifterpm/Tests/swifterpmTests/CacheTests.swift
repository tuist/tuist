import Foundation
import Testing
@testable import SwifterPMCore

struct CacheTests {
    @Test
    func cachePathsStayUnderProvidedRoot() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let pin = ResolvedPin(
                identity: "foo",
                kind: "remoteSourceControl",
                location: "https://github.com/example/foo.git",
                state: ResolvedState(
                    branch: nil,
                    revision: "abcdef1234567890",
                    version: "1.2.3"
                )
            )

            #expect(try cache.sourcePath(pin: pin).path.hasPrefix(root.path))
            #expect(
                try cache.archivePath(url: pin.location, revision: pin.revision()).path.hasPrefix(
                    root.path)
            )
            #expect(cache.remoteVersionsPath(location: pin.location).path.hasPrefix(root.path))
            #expect(
                cache.registryArchivePath(
                    identity: "example.package",
                    version: "1.2.3",
                    registryURL: "https://registry.example.com",
                    checksum: "abcdef1234567890"
                ).path
                    .hasPrefix(
                        root.path))
        }
    }

    @Test
    func initializesExpectedCacheDirectories() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)

            for path in [
                "sources",
                "archives",
                "registry/archives",
                "metadata/remotes",
                "locks",
                "virtual/checkouts",
                "artifacts",
            ] {
                #expect(try await fileSystem.exists(root.appendingPathComponent(path).absolutePath))
            }
            #expect(try await !cache.hasCachedSources())

            try await fileSystem.makeDirectory(
                at: root.appendingPathComponent("sources/example").absolutePath,
                options: [.createTargetParentDirectories]
            )
            #expect(try await cache.hasCachedSources())
        }
    }

    @Test
    func sourcePathRejectsRegistryPins() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let pin = ResolvedPin(
                identity: "example.package",
                kind: "registry",
                location: "",
                state: ResolvedState(branch: nil, revision: nil, version: nil)
            )

            #expect(throws: (any Error).self) {
                try cache.sourcePath(pin: pin)
            }
        }
    }

    @Test
    func registryCachePathsSeparateRegistriesAndVersions() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)

            let source = cache.registrySourcePath(
                identity: "example.package",
                version: "1.2.3",
                registryURL: "https://registry.example.com"
            )
            let otherRegistrySource = cache.registrySourcePath(
                identity: "example.package",
                version: "1.2.3",
                registryURL: "https://other.example.com"
            )
            let otherVersionSource = cache.registrySourcePath(
                identity: "example.package",
                version: "1.2.4",
                registryURL: "https://registry.example.com"
            )

            #expect(source != otherRegistrySource)
            #expect(source != otherVersionSource)
            // The checksum identifies the payload, not its location, so it lives in a marker
            // inside the directory. That keeps the path probeable without a registry request.
            #expect(!source.path.contains("abcdef1234567890"))
            #expect(
                cache.registryArchivePath(
                    identity: "example.package",
                    version: "1.2.3",
                    registryURL: "https://registry.example.com",
                    checksum: "abcdef1234567890"
                )
                    != cache.registryArchivePath(
                        identity: "example.package",
                        version: "1.2.3",
                        registryURL: "https://other.example.com",
                        checksum: "abcdef1234567890"
                    ))
        }
    }

    @Test
    func generatedCachePathsSanitizeMetadataComponents() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let pin = ResolvedPin(
                identity: "bad/identity",
                kind: "remoteSourceControl",
                location: "https://github.com/example/foo.git",
                state: ResolvedState(
                    branch: "feature/path\nwith-control",
                    revision: "abcdef1234567890",
                    version: nil
                )
            )

            let sourcePath = try cache.sourcePath(pin: pin).path
            let registrySourcePath = cache.registrySourcePath(
                identity: "example.bad/package",
                version: "1.2.3\nbeta",
                registryURL: "https://registry.example.com"
            ).path
            let registryArchivePath = cache.registryArchivePath(
                identity: "example.bad/package",
                version: "1.2.3\nbeta",
                registryURL: "https://registry.example.com",
                checksum: "abcdef1234567890"
            ).path
            let artifactPath = cache.binaryArtifactDirectory(
                identity: "bad/identity",
                targetName: "Foo\nBar",
                checksum: "abcdef1234567890"
            ).path

            #expect(sourcePath.contains("bad_identity/feature_path_with-control-abcdef1234567890"))
            #expect(registrySourcePath.contains("example.bad_package/1.2.3_beta-"))
            #expect(registryArchivePath.contains("-1.2.3_beta-"))
            #expect(registryArchivePath.hasSuffix("-abcdef1234567890.zip"))
            #expect(artifactPath.contains("bad_identity/Foo_Bar-abcdef123456"))
            for path in [sourcePath, registrySourcePath, registryArchivePath, artifactPath] {
                #expect(!path.contains("\n"))
                #expect(!path.contains("//"))
            }
        }
    }

    // A tag force-move between two commits that share their first 12 hex chars
    // would otherwise map two distinct revisions to the same cache directory,
    // and cachedSourceIsUsable would happily serve the stale Package.swift on
    // every subsequent resolve.
    @Test
    func sourcePathsDoNotCollideOnMatching12CharRevisionPrefixes() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let firstPin = ResolvedPin(
                identity: "flow",
                kind: "remoteSourceControl",
                location: "https://github.com/example/flow.git",
                state: ResolvedState(
                    branch: nil,
                    revision: "b6f9aac7a8d6000000000000000000000000aaaa",
                    version: "0.2.0"
                )
            )
            let secondPin = ResolvedPin(
                identity: "flow",
                kind: "remoteSourceControl",
                location: "https://github.com/example/flow.git",
                state: ResolvedState(
                    branch: nil,
                    revision: "b6f9aac7a8d6000000000000000000000000bbbb",
                    version: "0.2.0"
                )
            )

            let firstPath = try cache.sourcePath(pin: firstPin).path
            let secondPath = try cache.sourcePath(pin: secondPin).path

            #expect(firstPath != secondPath)
            #expect(firstPath.hasSuffix("-b6f9aac7a8d6000000000000000000000000aaaa"))
            #expect(secondPath.hasSuffix("-b6f9aac7a8d6000000000000000000000000bbbb"))
        }
    }

    @Test
    func archivePathsDoNotCollideOnMatching12CharRevisionPrefixes() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let url = "https://github.com/example/flow.git"

            let firstPath = cache.archivePath(
                url: url,
                revision: "aaaaaaaaaaaa0000000000000000000000000000"
            ).path
            let secondPath = cache.archivePath(
                url: url,
                revision: "aaaaaaaaaaaa1111111111111111111111111111"
            ).path

            #expect(firstPath != secondPath)
            #expect(firstPath.hasSuffix("-aaaaaaaaaaaa0000000000000000000000000000.tar.gz"))
            #expect(secondPath.hasSuffix("-aaaaaaaaaaaa1111111111111111111111111111.tar.gz"))
        }
    }

    @Test
    func archivePathsAreSharedAcrossEquivalentProviderLocationSpellings() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let revision = "abcdef1234567890abcdef1234567890abcdef12"

            #expect(
                cache.archivePath(url: "https://github.com/example/flow.git", revision: revision)
                    == cache.archivePath(url: "https://github.com/example/flow", revision: revision)
            )
            #expect(
                cache.archivePath(url: "https://source.example.com/example/flow.git", revision: revision)
                    != cache.archivePath(url: "https://source.example.com/example/flow", revision: revision)
            )
        }
    }

    @Test
    func pruneEvictsUnusedEntriesAndLeavesNativeSwiftPMFilesAndLocks() async throws {
        try await withTemporaryDirectory { root in
            _ = try await Cache(root: root)
            let now = Date()
            let old = now.addingTimeInterval(-31 * 24 * 60 * 60)
            let stale = try await cacheEntry(root, "sources/foo/1.0.0-aaa", bytes: 10, lastUsed: old)
            let fresh = try await cacheEntry(
                root, "sources/foo/2.0.0-bbb", bytes: 10, lastUsed: now.addingTimeInterval(-29 * 24 * 60 * 60)
            )
            let staleArchive = try await cacheFile(root, "archives/x-aaa.tar.gz", lastUsed: old)
            let nativeArtifact = try await cacheFile(root, "artifacts/https___example_com_A_zip", lastUsed: old)
            let nativeRepository = try await cacheEntry(root, "repositories/foo-123", bytes: 10, lastUsed: old)
            let lock = try await cacheFile(root, "locks/sources/abc.lock", lastUsed: old)

            try await CachePruner.prune(root: root, maxBytes: nil, now: now)

            #expect(!fileSystem.existsIncludingSymlinks(stale))
            #expect(!fileSystem.existsIncludingSymlinks(staleArchive))
            for kept in [fresh, nativeArtifact, nativeRepository, lock] {
                #expect(fileSystem.existsIncludingSymlinks(kept))
            }
        }
    }

    @Test
    func pruneSkipsAnEntryARestoreIsLinking() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let now = Date()
            let entry = try await cacheEntry(
                root, "artifacts/foo/Foo-abc", bytes: 10, lastUsed: now.addingTimeInterval(-60 * 24 * 60 * 60)
            )
            var restoreLock: PathLock? = try await cache.lock(namespace: "artifacts", key: entry.path, shared: true)

            try await CachePruner.prune(root: root, maxBytes: nil, now: now)
            #expect(fileSystem.existsIncludingSymlinks(entry))

            restoreLock = nil
            #expect(restoreLock == nil)
            try await CachePruner.prune(root: root, maxBytes: nil, now: now)
            #expect(!fileSystem.existsIncludingSymlinks(entry))
        }
    }

    @Test
    func pruneEvictsLeastRecentlyUsedEntriesToFitTheBudget() async throws {
        try await withTemporaryDirectory { root in
            _ = try await Cache(root: root)
            let now = Date()
            let megabyte = 1_000_000
            // Oldest first: a, b and c are past the grace period; d was used in the last hour.
            let a = try await cacheEntry(
                root, "sources/a/1-a", bytes: megabyte, lastUsed: now.addingTimeInterval(-4 * 3600)
            )
            let b = try await cacheEntry(
                root, "sources/b/1-b", bytes: megabyte, lastUsed: now.addingTimeInterval(-3 * 3600)
            )
            let c = try await cacheEntry(
                root, "artifacts/c/C-c", bytes: megabyte, lastUsed: now.addingTimeInterval(-2 * 3600)
            )
            let d = try await cacheEntry(
                root, "sources/d/1-d", bytes: megabyte, lastUsed: now.addingTimeInterval(-60)
            )

            try await CachePruner.prune(root: root, maxBytes: 2_500_000, now: now)

            #expect(!fileSystem.existsIncludingSymlinks(a))
            #expect(!fileSystem.existsIncludingSymlinks(b))
            #expect(fileSystem.existsIncludingSymlinks(c))
            #expect(fileSystem.existsIncludingSymlinks(d))

            // Even a budget nothing fits keeps entries in use.
            try await CachePruner.prune(root: root, maxBytes: 0, now: now)
            #expect(!fileSystem.existsIncludingSymlinks(c))
            #expect(fileSystem.existsIncludingSymlinks(d))
        }
    }

    @Test
    func pruneMeasuresAnEntryOnceAndRemeasuresAReplacedOne() async throws {
        try await withTemporaryDirectory { root in
            _ = try await Cache(root: root)
            let entry = try await cacheEntry(root, "sources/a/1-a", bytes: 1_000_000, lastUsed: Date())
            let pruneEntry = try #require(try await CachePruner.entries(root: root).first)
            let first = try #require(try await CachePruner.sizes(of: [pruneEntry])[pruneEntry.url])
            #expect(first >= 1_000_000)
            #expect(fileSystem.existsIncludingSymlinks(CachePruner.sizeRecord(for: pruneEntry.url)))

            try await fileSystem.removePath(entry)
            _ = try await cacheEntry(root, "sources/a/1-a", bytes: 3_000_000, lastUsed: Date())
            let second = try #require(try await CachePruner.sizes(of: [pruneEntry])[pruneEntry.url])
            #expect(second >= 3_000_000)
        }
    }

    private func cacheEntry(_ root: URL, _ path: String, bytes: Int, lastUsed: Date) async throws -> URL {
        let entry = root.appendingPathComponent(path)
        try await fileSystem.makeDirectory(at: entry.absolutePath, options: [.createTargetParentDirectories])
        try await fileSystem.atomicWrite(Data(repeating: 0x41, count: bytes), to: entry.appendingPathComponent("payload"))
        try await fileSystem.setFileTimes(of: entry.absolutePath, lastAccessDate: nil, lastModificationDate: lastUsed)
        return entry
    }

    private func cacheFile(_ root: URL, _ path: String, lastUsed: Date) async throws -> URL {
        let file = root.appendingPathComponent(path)
        try await fileSystem.atomicWrite(Data("x".utf8), to: file)
        try await fileSystem.setFileTimes(of: file.absolutePath, lastAccessDate: nil, lastModificationDate: lastUsed)
        return file
    }
}
