import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import SwifterPMCore

struct NativeWorkspaceTests {
    @Test(.inTemporaryDirectory)
    func privateCopiesIsolateSourcesArtifactsAndPreserveRealCheckouts() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let source = root.appendingPathComponent("source")
        let scratch = root.appendingPathComponent("scratch")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        let artifact = scratch.appendingPathComponent("artifacts/dependency/Foo")
        let real = scratch.appendingPathComponent("checkouts/UserCheckout")
        try await fileSystem.makeDirectory(at: source.absolutePath, options: [.createTargetParentDirectories])
        try await fileSystem.write(Data("original".utf8), to: source.appendingPathComponent("file").absolutePath)
        try await fileSystem.makeDirectory(
            at: checkout.deletingLastPathComponent().absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await fileSystem.makeDirectory(
            at: artifact.deletingLastPathComponent().absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await fileSystem.makeDirectory(at: real.absolutePath, options: [.createTargetParentDirectories])
        try await fileSystem.createSymbolicLink(from: checkout.absolutePath, to: source.absolutePath)
        try await fileSystem.createSymbolicLink(from: artifact.absolutePath, to: source.absolutePath)
        let owned = try await NativeWorkspace.prepare(scratchDir: scratch)
        #expect(owned == [checkout.lastPathComponent])
        #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
        #expect(fileSystem.isDirectoryAndNotSymlink(artifact))
        #expect(fileSystem.isDirectoryAndNotSymlink(real))
        try Data("changed".utf8).write(to: checkout.appendingPathComponent("file"))
        #expect(try await fileSystem.readFile(at: source.appendingPathComponent("file").absolutePath) == Data("original".utf8))
        #expect(try await fileSystem.readFile(at: artifact.appendingPathComponent("file").absolutePath) == Data("original".utf8))
    }

    @Test(.inTemporaryDirectory)
    func snapshotIgnoresDirtyIndexWorkingTreeAndAttributes() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let repo = root.appendingPathComponent("Dependency")
        let revision = try await repository(at: repo)
        let source = repo.appendingPathComponent("Sources/Dependency/file.swift")
        try await fileSystem.atomicWrite("wrong staged bytes", to: source)
        try await git(repo, ["add", "."])
        try await fileSystem.atomicWrite("* export-ignore\n* filter=invalid\n", to: repo.appendingPathComponent(".gitattributes"))
        try await fileSystem.atomicWrite("wrong manifest", to: repo.appendingPathComponent("Package.swift"))
        try await git(repo, ["update-index", "--assume-unchanged", "Sources/Dependency/file.swift"])
        let staging = root.appendingPathComponent("staging")
        let destination = staging.appendingPathComponent("package")
        try await fileSystem.makeDirectory(at: staging.absolutePath, options: [.createTargetParentDirectories])
        try await PinnedSourceSnapshot.write(from: repo, revision: revision, to: destination, staging: staging)
        #expect(try await fileSystem
            .readFile(at: destination.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) ==
            Data("original".utf8))
        #expect(try await fileSystem.readFile(at: source.absolutePath) == Data("wrong staged bytes".utf8))
        #expect(!fileSystem.existsIncludingSymlinks(destination.appendingPathComponent(".git")))
        #expect(try await fileSystem
            .readFile(at: destination.appendingPathComponent("Package.swift").absolutePath) != Data("wrong manifest".utf8))
    }

    @Test(.inTemporaryDirectory, arguments: [
        "",
        "# No submodules\n",
        "[submodule \"unused\"]\n\turl = https://example.com/unused.git\n",
    ])
    func gitmodulesWithoutPathsPublishesCacheAndRestoresFreshWorkspace(contents: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let scratch = root.appendingPathComponent("scratch")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        _ = try await repository(at: checkout)
        try await fileSystem.atomicWrite(contents, to: checkout.appendingPathComponent(".gitmodules"))
        try await git(checkout, ["add", ".gitmodules"])
        try await git(checkout, ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-qm", "gitmodules"])
        let revision = try await git(checkout, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = ResolvedPin(
            identity: "dependency", kind: "remoteSourceControl", location: "https://example.com/Dependency.git",
            state: .init(branch: nil, revision: revision, version: "1.0.0")
        )
        let resolved = ResolvedPins(originHash: nil, pins: [pin], version: 3)
        let cache = try await Cache(root: root.appendingPathComponent("cache"))
        try await WorkspaceRestorer.cacheNativeSourceCheckouts(
            scratchDir: scratch, cache: cache, mirrors: MirrorConfig(), resolved: resolved
        )
        let cached = try cache.sourcePath(pin: pin)
        #expect(try await fileSystem
            .readFile(at: cached.appendingPathComponent(".gitmodules").absolutePath) == Data(contents.utf8))
        #expect(try await fileSystem.readFile(
            at: cached.appendingPathComponent(WorkspaceRestorer.sourceRevisionMarkerFilename).absolutePath
        ) == Data(revision.utf8))
        #expect(!fileSystem.existsIncludingSymlinks(cached.appendingPathComponent(".git")))
        try await ResolvedFile.write(packageDir: root, resolved: resolved, mirrors: MirrorConfig())
        try await fileSystem.removePath(scratch)
        #expect(try await !PackageResolver.shouldUseNativeColdPath(
            packageDir: root, cacheRoot: cache.root, registryConfig: RegistryConfig()
        ))
        try await WorkspaceRestorer.restorePackage(
            scratchDir: scratch, cache: cache, registryConfig: RegistryConfig(), mirrors: MirrorConfig(),
            resolved: resolved, progress: nil, disableSandbox: true
        )
        #expect(try await fileSystem
            .readFile(at: checkout.appendingPathComponent(".gitmodules").absolutePath) == Data(contents.utf8))
    }

    @Test(.inTemporaryDirectory)
    func malformedGitmodulesStillRejectsSnapshot() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let repo = root.appendingPathComponent("Dependency")
        _ = try await repository(at: repo)
        try await fileSystem.atomicWrite("[submodule \"broken\"\n", to: repo.appendingPathComponent(".gitmodules"))
        try await git(repo, ["add", ".gitmodules"])
        try await git(
            repo,
            ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-qm", "malformed gitmodules"]
        )
        let revision = try await git(repo, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let staging = root.appendingPathComponent("staging")
        try await fileSystem.makeDirectory(at: staging.absolutePath, options: [.createTargetParentDirectories])
        await #expect(throws: (any Error).self) {
            try await PinnedSourceSnapshot.write(
                from: repo, revision: revision, to: staging.appendingPathComponent("package"), staging: staging
            )
        }
    }

    @Test(.inTemporaryDirectory, arguments: [false, true], [false, true])
    func ownedDirtyNativeCheckoutPublishesCanonicalSources(legacyDestination: Bool, localSourceControl: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let scratch = root.appendingPathComponent("scratch")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        let revision = try await repository(at: checkout)
        try await git(checkout, ["tag", "1.0.0"])
        let origin = root.appendingPathComponent("Dependency")
        if localSourceControl {
            try await SystemProcess.run("/usr/bin/git", ["clone", "--no-local", checkout.path, origin.path])
        }
        try await fileSystem.atomicWrite("wrong", to: checkout.appendingPathComponent("Sources/Dependency/file.swift"))
        try await git(checkout, ["add", "."])
        let pin = ResolvedPin(
            identity: "dependency",
            kind: localSourceControl ? "localSourceControl" : "remoteSourceControl",
            location: localSourceControl ? origin.path : "https://example.com/Dependency.git",
            state: .init(branch: nil, revision: revision, version: "1.0.0")
        )
        var resolved = ResolvedPins(originHash: nil, pins: [pin], version: 3)
        resolved.nativeOwnedCheckouts = [checkout.lastPathComponent]
        let cache = try await Cache(root: root.appendingPathComponent("cache"))
        let cached = try cache.sourcePath(pin: pin)
        if legacyDestination {
            try await fileSystem.makeDirectory(
                at: cached.deletingLastPathComponent().absolutePath,
                options: [.createTargetParentDirectories]
            )
            try await fileSystem.copyPrivately(source: checkout, destination: cached)
            try await fileSystem.atomicWrite(
                revision,
                to: cached.appendingPathComponent(WorkspaceRestorer.sourceRevisionMarkerFilename)
            )
        }
        try await WorkspaceRestorer.cacheNativeSourceCheckouts(
            scratchDir: scratch,
            cache: cache,
            mirrors: MirrorConfig(),
            resolved: resolved
        )
        #expect(try await fileSystem
            .readFile(at: checkout.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("original".utf8))
        #expect(fileSystem
            .existsIncludingSymlinks(checkout.appendingPathComponent(".git")) == (legacyDestination && localSourceControl))
        if legacyDestination, localSourceControl {
            try await git(checkout, ["status", "--porcelain"])
            try await git(checkout, ["fsck"])
            #expect(try await git(checkout, ["describe", "--tags", "--exact-match"])
                .trimmingCharacters(in: .whitespacesAndNewlines) == "1.0.0")
        }
        if legacyDestination {
            #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
            #expect(try await fileSystem
                .readFile(at: cached.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("wrong".utf8))
            #expect(fileSystem.existsIncludingSymlinks(cached.appendingPathComponent(".git")))
        } else {
            #expect(fileSystem.isSymlink(checkout))
            #expect(!fileSystem.existsIncludingSymlinks(cached.appendingPathComponent(".git")))
        }
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func unmanagedDirtyCheckoutIsPreservedAndNotStamped(unreadableMetadata: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let scratch = root.appendingPathComponent("scratch")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        let revision = try await repository(at: checkout)
        try await fileSystem.atomicWrite("user edits", to: checkout.appendingPathComponent("Sources/Dependency/file.swift"))
        if unreadableMetadata {
            try await fileSystem.atomicWrite("invalid HEAD", to: checkout.appendingPathComponent(".git/HEAD"))
        }
        let pin = ResolvedPin(
            identity: "dependency",
            kind: "remoteSourceControl",
            location: "https://example.com/Dependency.git",
            state: .init(branch: nil, revision: revision, version: "1.0.0")
        )
        let cache = try await Cache(root: root.appendingPathComponent("cache"))
        do {
            try await WorkspaceRestorer.cacheNativeSourceCheckouts(
                scratchDir: scratch,
                cache: cache,
                mirrors: MirrorConfig(),
                resolved: .init(originHash: nil, pins: [pin], version: 3)
            )
            Issue.record("Expected modified native checkout to be preserved")
        } catch {
            #expect(String(describing: error).contains("preserving modified"))
        }
        #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
        #expect(try await fileSystem
            .readFile(at: checkout.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) ==
            Data("user edits".utf8))
        #expect(try await !fileSystem.exists(cache.sourcePath(pin: pin).absolutePath))
    }

    @Test(.inTemporaryDirectory)
    func initializedSubmodulesUsePinnedObjectsAndContainNoGitMetadata() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let repo = root.appendingPathComponent("Dependency")
        let submodule = root.appendingPathComponent("Submodule")
        _ = try await repository(at: submodule)
        try await fileSystem.atomicWrite("", to: submodule.appendingPathComponent(".gitmodules"))
        try await git(submodule, ["add", ".gitmodules"])
        try await git(
            submodule,
            ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-qm", "empty gitmodules"]
        )
        _ = try await repository(at: repo)
        try await git(repo, ["-c", "protocol.file.allow=always", "submodule", "add", submodule.path, "vendor"])
        try await git(repo, ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-m", "submodule"])
        let revision = try await git(repo, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await fileSystem.atomicWrite("wrong child", to: repo.appendingPathComponent("vendor/Sources/Dependency/file.swift"))
        let staging = root.appendingPathComponent("staging")
        let destination = staging.appendingPathComponent("package")
        try await fileSystem.makeDirectory(at: staging.absolutePath, options: [.createTargetParentDirectories])
        try await PinnedSourceSnapshot.write(from: repo, revision: revision, to: destination, staging: staging)
        #expect(try await fileSystem
            .readFile(at: destination.appendingPathComponent("vendor/Sources/Dependency/file.swift").absolutePath) ==
            Data("original".utf8))
        #expect(!fileSystem.existsIncludingSymlinks(destination.appendingPathComponent("vendor/.git")))
    }

    @Test(.inTemporaryDirectory)
    func cleanIgnoredManifestCacheDoesNotCountAsUserEdits() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let repo = root.appendingPathComponent("Dependency")
        _ = try await repository(at: repo)
        try await fileSystem.atomicWrite(".build/\n", to: repo.appendingPathComponent(".gitignore"))
        try await git(repo, ["add", "."])
        try await git(repo, ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-qm", "ignore"])
        let revision = try await git(repo, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await fileSystem.atomicWrite("{}", to: repo.appendingPathComponent(".build/swifterpm/manifests/package.json"))
        try await fileSystem.atomicWrite("cache directory", to: repo.appendingPathComponent(".build/CACHEDIR.TAG"))
        try await fileSystem.atomicWrite("native", to: repo.appendingPathComponent(".build/.buildSystem_debug"))
        #expect(try await PinnedSourceSnapshot.isPristine(repo, revision: revision))
        try await fileSystem.atomicWrite("user data", to: repo.appendingPathComponent(".build/user.txt"))
        #expect(try await !PinnedSourceSnapshot.isPristine(repo, revision: revision))
    }

    @Test(.inTemporaryDirectory)
    func snapshotFailureKeepsOwnedNativeCheckoutWithoutStampingCache() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let scratch = root.appendingPathComponent("scratch")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        _ = try await repository(at: checkout)
        let pin = ResolvedPin(
            identity: "dependency",
            kind: "remoteSourceControl",
            location: "https://example.com/Dependency.git",
            state: .init(branch: nil, revision: String(repeating: "a", count: 40), version: "1.0.0")
        )
        var resolved = ResolvedPins(originHash: nil, pins: [pin], version: 3)
        resolved.nativeOwnedCheckouts = ["Dependency"]
        let cache = try await Cache(root: root.appendingPathComponent("cache"))
        try await WorkspaceRestorer.cacheNativeSourceCheckouts(
            scratchDir: scratch,
            cache: cache,
            mirrors: MirrorConfig(),
            resolved: resolved
        )
        #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
        #expect(fileSystem.existsIncludingSymlinks(checkout.appendingPathComponent(".git")))
        #expect(try await !fileSystem.exists(cache.sourcePath(pin: pin).absolutePath))
    }

    @Test(.inTemporaryDirectory)
    func editedStateIsNotRewritten() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let scratch = root.appendingPathComponent("scratch")
        let state = Data(#"{"object":{"dependencies":[{"state":{"name":"edited"}}]},"version":7}"#.utf8)
        let path = scratch.appendingPathComponent("workspace-state.json")
        try await fileSystem.write(state, to: path.absolutePath)
        do {
            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: root,
                scratchDir: scratch,
                mirrors: MirrorConfig(),
                resolved: .init(originHash: nil, pins: [], version: 3),
                disableSandbox: true
            )
            Issue.record("Expected edited state to be preserved")
        } catch {
            #expect(String(describing: error).contains("edited dependencies"))
        }
        #expect(try await fileSystem.readFile(at: path.absolutePath) == state)
    }

    @Test(.inTemporaryDirectory)
    func unmanagedGitFreeDirectoryIsNotDeleted() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let scratch = root.appendingPathComponent("scratch")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        try await writeMinimalPackageManifest(at: checkout, name: "Dependency")
        let pin = ResolvedPin(
            identity: "dependency",
            kind: "remoteSourceControl",
            location: "https://example.com/Dependency.git",
            state: .init(branch: nil, revision: String(repeating: "a", count: 40), version: "1.0.0")
        )
        let cache = try await Cache(root: root.appendingPathComponent("cache"))
        do {
            try await WorkspaceRestorer.cacheNativeSourceCheckouts(
                scratchDir: scratch,
                cache: cache,
                mirrors: MirrorConfig(),
                resolved: .init(originHash: nil, pins: [pin], version: 3)
            )
            Issue.record("Expected unmarked real checkout to be preserved")
        } catch {
            #expect(String(describing: error).contains("preserving modified"))
        }
        #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
        #expect(try await fileSystem.exists(checkout.appendingPathComponent("Package.swift").absolutePath))
    }

    @Test(.inTemporaryDirectory, arguments: [false, true], [false, true])
    func legacyDirtySharedGitTreeIsRebuiltPrivatelyAndReused(missingObjects: Bool, annotatedTag: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let repo = root.appendingPathComponent("origin")
        let revision = try await repository(at: repo)
        if annotatedTag {
            try await git(
                repo,
                ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "tag", "-a", "1.0.0", "-m", "release"]
            )
        } else {
            try await git(repo, ["tag", "1.0.0"])
        }
        try await fileSystem.atomicWrite("new commit", to: repo.appendingPathComponent("Sources/Dependency/file.swift"))
        try await git(repo, ["add", "."])
        try await git(repo, ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-qm", "next"])
        let next = try await git(repo, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = ResolvedPin(
            identity: "dependency",
            kind: "localSourceControl",
            location: repo.path,
            state: .init(branch: nil, revision: revision, version: "1.0.0")
        )
        let cache = try await Cache(root: root.appendingPathComponent("cache"))
        let cached = try cache.sourcePath(pin: pin)
        try await fileSystem.makeDirectory(
            at: cached.deletingLastPathComponent().absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await SystemProcess.run("/usr/bin/git", ["clone", "--shared", "--no-checkout", repo.path, cached.path])
        try await git(cached, ["checkout", "--detach", revision])
        try await git(cached, ["read-tree", "--reset", "-u", next])
        try await fileSystem.atomicWrite(
            revision,
            to: cached.appendingPathComponent(WorkspaceRestorer.sourceRevisionMarkerFilename)
        )
        if missingObjects {
            try await fileSystem.atomicWrite(
                root.appendingPathComponent("missing-objects").path,
                to: cached.appendingPathComponent(".git/objects/info/alternates")
            )
        }
        let indexBefore = try await fileSystem.readFile(at: cached.appendingPathComponent(".git/index").absolutePath)
        let logBefore = try await fileSystem.readFile(at: cached.appendingPathComponent(".git/logs/HEAD").absolutePath)
        let scratch = root.appendingPathComponent("scratch")
        let resolved = ResolvedPins(originHash: nil, pins: [pin], version: 3)
        try await WorkspaceRestorer.restorePackage(
            scratchDir: scratch,
            cache: cache,
            registryConfig: RegistryConfig(),
            mirrors: MirrorConfig(),
            resolved: resolved,
            progress: nil,
            disableSandbox: true
        )
        let checkout = scratch.appendingPathComponent("checkouts/origin")
        #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
        #expect(try await fileSystem
            .readFile(at: checkout.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("original".utf8))
        #expect(try await fileSystem
            .readFile(at: cached.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("new commit".utf8))
        #expect(try await fileSystem.readFile(at: cached.appendingPathComponent(".git/index").absolutePath) == indexBefore)
        #expect(try await fileSystem.readFile(at: cached.appendingPathComponent(".git/logs/HEAD").absolutePath) == logBefore)
        #expect(try await git(checkout, ["describe", "--tags", "--exact-match"])
            .trimmingCharacters(in: .whitespacesAndNewlines) == "1.0.0")
        let inode = try await SystemProcess.output("/usr/bin/stat", ["-f", "%i", checkout.path])
        try await WorkspaceRestorer.restorePackage(
            scratchDir: scratch,
            cache: cache,
            registryConfig: RegistryConfig(),
            mirrors: MirrorConfig(),
            resolved: resolved,
            progress: nil,
            disableSandbox: true
        )
        #expect(try await SystemProcess.output("/usr/bin/stat", ["-f", "%i", checkout.path]) == inode)
        try await fileSystem.removePath(cached)
        try await fileSystem.removePath(repo)
        try await git(checkout, ["status", "--porcelain"])
        try await git(checkout, ["fsck"])
        #expect(try await PinnedSourceSnapshot.isPristine(checkout, revision: revision))
    }

    @Test(.inTemporaryDirectory)
    func preparationOwnershipSurvivesSymlinkedScratchSpelling() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let repo = root.appendingPathComponent("Dependency")
        let revision = try await repository(at: repo)
        try await fileSystem.atomicWrite("damaged", to: repo.appendingPathComponent("Sources/Dependency/file.swift"))
        try await git(repo, ["add", "."])
        let scratch = root.appendingPathComponent("scratch")
        let alias = root.appendingPathComponent("alias")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        try await fileSystem.makeDirectory(
            at: checkout.deletingLastPathComponent().absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await fileSystem.createSymbolicLink(from: checkout.absolutePath, to: repo.absolutePath)
        try await fileSystem.createSymbolicLink(from: alias.absolutePath, to: scratch.absolutePath)
        let owned = try await NativeWorkspace.prepare(scratchDir: alias)
        #expect(!fileSystem.existsIncludingSymlinks(checkout))
        try await SystemProcess.run("/usr/bin/git", ["clone", "--shared", repo.path, checkout.path])
        try await fileSystem.atomicWrite(
            "native dirty bytes",
            to: checkout.appendingPathComponent("Sources/Dependency/file.swift")
        )
        let pin = ResolvedPin(
            identity: "dependency",
            kind: "remoteSourceControl",
            location: "https://example.com/Dependency.git",
            state: .init(branch: nil, revision: revision, version: "1.0.0")
        )
        var resolved = ResolvedPins(originHash: nil, pins: [pin], version: 3)
        resolved.nativeOwnedCheckouts = owned
        let cache = try await Cache(root: root.appendingPathComponent("cache"))
        try await WorkspaceRestorer.cacheNativeSourceCheckouts(
            scratchDir: scratch,
            cache: cache,
            mirrors: MirrorConfig(),
            resolved: resolved
        )
        #expect(try await fileSystem
            .readFile(at: checkout.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("original".utf8))
        #expect(try await fileSystem
            .readFile(at: repo.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("damaged".utf8))
    }

    @Test(.inTemporaryDirectory, arguments: [true, false])
    func privateCopyIsolationDoesNotDependOnDirectoryClone(preferClone: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("private")
        let file = source.appendingPathComponent("file")
        try await fileSystem.atomicWrite("original", to: file)
        try await fileSystem.copyPrivately(source: source, destination: destination, preferClone: preferClone)
        try await SystemProcess.run("/bin/chmod", ["600", destination.appendingPathComponent("file").path])
        // dd opens the existing inode, unlike atomicWrite which replaces it.
        try await SystemProcess.run(
            "/bin/dd",
            ["if=/dev/zero", "of=\(destination.appendingPathComponent("file").path)", "bs=1", "count=1", "conv=notrunc"]
        )
        #expect(try await fileSystem.readFile(at: file.absolutePath) == Data("original".utf8))
        #expect(fileSystem.isDirectoryAndNotSymlink(destination))
    }

    @Test(.inTemporaryDirectory, arguments: [50, 200])
    func largeSyntheticNativeHandoffRemainsPrivate(packageCount: Int) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let source = root.appendingPathComponent("source")
        let scratch = root.appendingPathComponent("scratch")
        let checkouts = scratch.appendingPathComponent("checkouts")
        try await fileSystem.makeDirectory(at: checkouts.absolutePath, options: [.createTargetParentDirectories])
        for index in 0 ..< 265 {
            try await fileSystem.write(
                Data(repeating: UInt8(index % 255), count: 25600),
                to: source.appendingPathComponent("files/\(index)").absolutePath
            )
        }
        for index in 0 ..< packageCount {
            try await fileSystem.createSymbolicLink(
                from: checkouts.appendingPathComponent("dep\(index)").absolutePath,
                to: source.absolutePath
            )
        }
        let clock = ContinuousClock()
        let start = clock.now
        let owned = try await NativeWorkspace.prepare(scratchDir: scratch)
        let handoff = start.duration(to: clock.now)
        let warmStart = clock.now
        let reused = try await NativeWorkspace.prepare(scratchDir: scratch)
        print(
            "Synthetic native handoff \(packageCount) x 265 files/6.8MB: \(handoff); repeat private preparation: \(warmStart.duration(to: clock.now))"
        )
        #expect(owned.count == packageCount)
        #expect(reused.isEmpty)
        for index in 0 ..< packageCount {
            #expect(fileSystem.isDirectoryAndNotSymlink(checkouts.appendingPathComponent("dep\(index)")))
        }
        try await SystemProcess.run(
            "/bin/dd",
            ["if=/dev/zero", "of=\(checkouts.appendingPathComponent("dep0/files/1").path)", "bs=1", "count=1", "conv=notrunc"]
        )
        #expect(try await fileSystem.readFile(at: source.appendingPathComponent("files/1").absolutePath) == Data(
            repeating: 1,
            count: 25600
        ))
    }

    @Test(.inTemporaryDirectory)
    func failedStagedReplacementRestoresPreviousCheckout() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let checkout = root.appendingPathComponent("checkout")
        try await fileSystem.atomicWrite("user data", to: checkout.appendingPathComponent("file"))
        do {
            try await fileSystem.replaceWithStagedItem(source: root.appendingPathComponent("missing"), destination: checkout)
            Issue.record("Expected replacement failure")
        } catch {
            #expect(try await fileSystem
                .readFile(at: checkout.appendingPathComponent("file").absolutePath) == Data("user data".utf8))
        }
    }

    @Test(.inTemporaryDirectory)
    func cancelledStagedReplacementKeepsOriginalAndStaging() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let checkout = root.appendingPathComponent("checkout")
        let staged = root.appendingPathComponent("staged")
        try await fileSystem.atomicWrite("old", to: checkout.appendingPathComponent("file"))
        try await fileSystem.atomicWrite("new", to: staged.appendingPathComponent("file"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await fileSystem.replaceWithStagedItem(source: staged, destination: checkout)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await fileSystem.readFile(at: checkout.appendingPathComponent("file").absolutePath) == Data("old".utf8))
        #expect(try await fileSystem.readFile(at: staged.appendingPathComponent("file").absolutePath) == Data("new".utf8))
    }

    @Test(.inTemporaryDirectory)
    func cleanOlderNativeCheckoutRequestsNativeUpdateButUnpublishedWorkDoesNot() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let repo = root.appendingPathComponent("Dependency")
        let old = try await repository(at: repo)
        try await git(repo, ["tag", "1.0.0"])
        try await fileSystem.atomicWrite("next", to: repo.appendingPathComponent("Sources/Dependency/file.swift"))
        try await git(repo, ["add", "."])
        try await git(repo, ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-qm", "next"])
        let next = try await git(repo, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await git(repo, ["tag", "2.0.0"])
        try await git(repo, ["checkout", "--detach", old])
        #expect(try await PinnedSourceSnapshot.canReplaceOlderCheckout(repo, revision: next))
        try await fileSystem.atomicWrite("user edit", to: repo.appendingPathComponent("Sources/Dependency/file.swift"))
        #expect(try await !PinnedSourceSnapshot.canReplaceOlderCheckout(repo, revision: next))
        try await git(repo, ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-am", "user commit"])
        #expect(try await !PinnedSourceSnapshot.canReplaceOlderCheckout(repo, revision: next))
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func stagedReplacementHandlesDanglingCheckoutLinks(failReplacement: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let checkout = root.appendingPathComponent("checkout")
        let missingTarget = root.appendingPathComponent("missing-target")
        let staged = root.appendingPathComponent("staged")
        try await fileSystem.createSymbolicLink(from: checkout.absolutePath, to: missingTarget.absolutePath)
        try await fileSystem.atomicWrite("new", to: staged.appendingPathComponent("file"))
        do {
            try await fileSystem.replaceWithStagedItem(
                source: failReplacement ? root.appendingPathComponent("missing-replacement") : staged,
                destination: checkout
            )
            #expect(!failReplacement)
            #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
            #expect(try await fileSystem.readFile(at: checkout.appendingPathComponent("file").absolutePath) == Data("new".utf8))
        } catch {
            #expect(failReplacement)
            #expect(fileSystem.isSymlink(checkout))
        }
        #expect(try await !fileSystem.exists(missingTarget.absolutePath))
    }

    @Test(.inTemporaryDirectory)
    func cancellationAfterBackupRestoresOriginalCheckout() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let checkout = root.appendingPathComponent("checkout")
        let staged = root.appendingPathComponent("staged")
        try await fileSystem.atomicWrite("old", to: checkout.appendingPathComponent("file"))
        try await fileSystem.atomicWrite("new", to: staged.appendingPathComponent("file"))
        let task = Task {
            try await fileSystem.replaceWithStagedItem(source: staged, destination: checkout) { _, destination in
                #expect(!fileSystem.existsIncludingSymlinks(destination))
                withUnsafeCurrentTask { $0?.cancel() }
                throw CancellationError()
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await fileSystem.readFile(at: checkout.appendingPathComponent("file").absolutePath) == Data("old".utf8))
        #expect(try await fileSystem.readFile(at: staged.appendingPathComponent("file").absolutePath) == Data("new".utf8))
    }

    @Test(.inTemporaryDirectory)
    func failedNativeResolutionDoesNotStrandDamagedLegacyGitCopy() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let source = root.appendingPathComponent("Dependency")
        _ = try await repository(at: source)
        try await git(source, ["tag", "1.0.0"])
        try await fileSystem.atomicWrite("damaged", to: source.appendingPathComponent("Sources/Dependency/file.swift"))
        let scratch = root.appendingPathComponent("scratch")
        let checkout = scratch.appendingPathComponent("checkouts/Dependency")
        try await fileSystem.makeDirectory(
            at: checkout.deletingLastPathComponent().absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await fileSystem.createSymbolicLink(from: checkout.absolutePath, to: source.absolutePath)
        let package = root.appendingPathComponent("App")
        try await fileSystem.atomicWrite(
            "// swift-tools-version: 6.0\ninvalid syntax",
            to: package.appendingPathComponent("Package.swift")
        )
        do {
            _ = try await PackageResolver.resolveWithSwiftPackageManagerProcess(
                packageDir: package,
                scratchDir: scratch,
                cacheDir: root.appendingPathComponent("cache"),
                registryConfigurationPath: nil,
                defaultRegistryURL: nil,
                disableSandbox: true,
                scmToRegistryTransformation: .disabled,
                useExistingResolvedFile: true,
                writeResolvedFile: true,
                forwardOutput: false
            )
            Issue.record("Expected native manifest failure")
        } catch {
            #expect(!fileSystem.existsIncludingSymlinks(checkout))
        }
        try await fileSystem.atomicWrite(
            "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"App\", dependencies: [.package(url: \"\(source.path)\", exact: \"1.0.0\")])",
            to: package.appendingPathComponent("Package.swift")
        )
        let resolved = try await PackageResolver.resolveWithSwiftPackageManagerProcess(
            packageDir: package,
            scratchDir: scratch,
            cacheDir: root.appendingPathComponent("cache"),
            registryConfigurationPath: nil,
            defaultRegistryURL: nil,
            disableSandbox: true,
            scmToRegistryTransformation: .disabled,
            useExistingResolvedFile: true,
            writeResolvedFile: true,
            forwardOutput: false
        )
        #expect(resolved.nativeOwnedCheckouts.contains("Dependency"))
        #expect(try await fileSystem
            .readFile(at: checkout.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("original".utf8))
        #expect(try await fileSystem
            .readFile(at: source.appendingPathComponent("Sources/Dependency/file.swift").absolutePath) == Data("damaged".utf8))
    }

    @Test(.inTemporaryDirectory)
    func failedRollbackKeepsRecoverableBackupWithoutOverwritingAnotherCheckout() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let checkout = root.appendingPathComponent("checkout")
        let staged = root.appendingPathComponent("staged")
        try await fileSystem.atomicWrite("old", to: checkout.appendingPathComponent("file"))
        try await fileSystem.atomicWrite("new", to: staged.appendingPathComponent("file"))
        do {
            try await fileSystem.replaceWithStagedItem(source: staged, destination: checkout) { _, destination in
                try await fileSystem.atomicWrite("other checkout", to: destination.appendingPathComponent("file"))
                throw ToolError.message("forced replacement failure")
            }
            Issue.record("Expected rollback failure")
        } catch {
            #expect(String(describing: error).contains("previous data is preserved at"))
        }
        let directories = try await fileSystem.contentsOfDirectory(at: root)
        let backupDirectory = try #require(directories.first { $0.lastPathComponent.hasPrefix(".tmp-") })
        #expect(try await fileSystem
            .readFile(at: backupDirectory.appendingPathComponent("previous/file").absolutePath) == Data("old".utf8))
        #expect(try await fileSystem
            .readFile(at: checkout.appendingPathComponent("file").absolutePath) == Data("other checkout".utf8))
    }

    @discardableResult
    private func repository(at repo: URL) async throws -> String {
        try await writeMinimalPackageManifest(at: repo, name: "Dependency")
        try await fileSystem.atomicWrite("original", to: repo.appendingPathComponent("Sources/Dependency/file.swift"))
        try await git(repo, ["init", "-q"])
        try await git(repo, ["add", "."])
        try await git(repo, ["-c", "user.name=Tests", "-c", "user.email=tests@example.com", "commit", "-qm", "initial"])
        return try await git(repo, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func git(_ repo: URL, _ arguments: [String]) async throws -> String {
        try await SystemProcess.output("/usr/bin/git", ["-C", repo.path] + arguments)
    }
}
