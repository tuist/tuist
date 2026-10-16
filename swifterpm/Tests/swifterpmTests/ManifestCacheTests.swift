import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import SwifterPMCore

struct ManifestCacheTests {
    private actor Probe {
        private(set) var calls = 0

        func identity(fails: Bool) throws -> String {
            calls += 1
            if fails { throw ToolError.message("unavailable compiler") }
            return "compiler"
        }
    }

    @Test(.inTemporaryDirectory)
    func contextDoesNotProbeUntilCacheInputsAreNeeded() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        let probe = Probe()
        let identity = ManifestCache.ToolchainIdentity { try await probe.identity(fails: false) }
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: nil, toolchain: identity) {
            #expect(await probe.calls == 0)
        }
        #expect(await probe.calls == 0)
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func concurrentInputsShareOneProbeIncludingFailure(fails: Bool) async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        try await writeMinimalPackageManifest(at: package, name: "Root")
        let probe = Probe()
        let identity = ManifestCache.ToolchainIdentity { try await probe.identity(fails: fails) }
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: nil, toolchain: identity) {
            await withTaskGroup(of: String?.self) { group in
                for _ in 0 ..< 20 {
                    group.addTask { try? await ManifestCache.inputs(packageDir: package, disableSandbox: false) }
                }
                for await result in group {
                    #expect((result == nil) == fails)
                }
            }
            #expect(await probe.calls == 1)
            _ = try? await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            #expect(await probe.calls == 1)
        }
        let retry = ManifestCache.ToolchainIdentity { try await probe.identity(fails: fails) }
        _ = try? await retry.value()
        #expect(await probe.calls == 2)
    }

    @Test(.inTemporaryDirectory)
    func standardizedPathsShareCacheEntries() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let package = root.appendingPathComponent("Local")
        let alternate = root.appendingPathComponent("Root/../Local")
        try await ManifestCache.withContext(packageDirectory: root, scratchDirectory: nil) {
            #expect(ManifestLoader.cacheFilePath(packageDir: package) == ManifestLoader.cacheFilePath(packageDir: alternate))
            #expect(ManifestLoader.localCacheFilePath(rootPackageDir: root, packageDir: package)
                == ManifestLoader.localCacheFilePath(rootPackageDir: root, packageDir: alternate))
        }
    }

    @Test(.inTemporaryDirectory)
    func unavailableToolchainIdentityStillEvaluatesManifests() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        try await writeMinimalPackageManifest(at: package, name: "Root")
        let probe = Probe()
        let identity = ManifestCache.ToolchainIdentity { try await probe.identity(fails: true) }
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: nil, toolchain: identity) {
            try await writePackageInfo(package: package, scratch: package.appendingPathComponent(".build"))
            let output = package.appendingPathComponent(".build/swifterpm/package-info/root.json")
            let data = try await fileSystem.readFile(at: output.absolutePath)
            #expect(ManifestParser.packageName(try JSONSerialization.jsonObject(with: data)) == "Root")
            #expect(try await fileSystem.exists(ManifestCache.sidecar(output).absolutePath) == false)
            #expect(await probe.calls == 1)
        }
    }

    @Test(.inTemporaryDirectory)
    func workspaceStatePrunesOnlyObsoleteManifestEntries() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let scratch = root.appendingPathComponent("scratch")
        let removed = root.appendingPathComponent("removed")
        try await writeMinimalPackageManifest(at: root, name: "Root")
        try await ManifestCache.withContext(packageDirectory: root, scratchDirectory: scratch) {
            let stale = ManifestLoader.cacheFilePath(packageDir: removed)
            try await ManifestCache.write(Data("{}".utf8), at: stale, inputs: "old")
            let unrelated = scratch.appendingPathComponent("swifterpm/manifests/packages/unrelated/file")
            try await fileSystem.atomicWrite("keep", to: unrelated)
            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: root, scratchDir: scratch, mirrors: MirrorConfig(),
                resolved: ResolvedPins(originHash: nil, pins: [], version: 3), disableSandbox: true
            )
            #expect(try await fileSystem.exists(stale.absolutePath) == false)
            #expect(try await fileSystem.exists(unrelated.absolutePath))
            #expect(try await fileSystem.exists(ManifestLoader.cacheFilePath(packageDir: root).absolutePath))
        }
    }

    @Test(.inTemporaryDirectory)
    func identicalCheckoutContentsReuseDumpAndPackageInfo() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        try await writeMinimalPackageManifest(at: package, name: "Root")
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: nil) {
            let first = try await ManifestLoader.dumpPackageJSON(packageDir: package, disableSandbox: true)
            let cache = ManifestLoader.cacheFilePath(packageDir: package)
            let before = try await fileSystem.fileMetadata(at: cache.absolutePath)?.lastModificationDate
            let manifest = package.appendingPathComponent("Package.swift")
            let contents = try await fileSystem.readFile(at: manifest.absolutePath)
            try await Task.sleep(for: .milliseconds(20))
            try await fileSystem.atomicWrite(contents, to: manifest)

            let second = try await ManifestLoader.dumpPackageJSON(packageDir: package, disableSandbox: true)
            #expect(first == second)
            #expect(try await fileSystem.fileMetadata(at: cache.absolutePath)?.lastModificationDate == before)

            let scratch = package.appendingPathComponent(".build")
            try await writePackageInfo(package: package, scratch: scratch)
            let packageInfo = scratch.appendingPathComponent("swifterpm/package-info/root.json")
            let infoBefore = try await fileSystem.fileMetadata(at: packageInfo.absolutePath)?.lastModificationDate
            try await Task.sleep(for: .milliseconds(20))
            try await fileSystem.atomicWrite(contents, to: manifest)
            try await writePackageInfo(package: package, scratch: scratch)
            #expect(try await fileSystem.fileMetadata(at: packageInfo.absolutePath)?.lastModificationDate == infoBefore)
        }
    }

    @Test(.inTemporaryDirectory)
    func changedContentsInvalidateEvenWithoutTimestampComparison() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        try await writeMinimalPackageManifest(at: package, name: "Before")
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: nil) {
            _ = try await ManifestLoader.dumpPackageJSON(packageDir: package, disableSandbox: true)
            try await writeMinimalPackageManifest(at: package, name: "After")
            let manifest = try await ManifestLoader.dumpPackage(packageDir: package, disableSandbox: true)
            #expect(ManifestParser.packageName(manifest) == "After")
        }
    }

    @Test(.inTemporaryDirectory)
    func versionSpecificManifestAdditionChangeAndRemovalInvalidate() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        try await writeMinimalPackageManifest(at: package, name: "Base")
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: nil) {
            let base = try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            let variant = package.appendingPathComponent("Package@swift-6.0.swift")
            try await fileSystem.atomicWrite("first", to: variant)
            let added = try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            try await fileSystem.atomicWrite("other", to: variant)
            let changed = try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            try await fileSystem.remove(variant.absolutePath)
            let removed = try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            #expect(base != added)
            #expect(added != changed)
            #expect(removed == base)
        }
    }

    @Test(.inTemporaryDirectory)
    func environmentToolchainSandboxAndMirrorsInvalidate() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        try await writeMinimalPackageManifest(at: package, name: "Root")
        try await ManifestCache.$toolchain.withValue(ManifestCache.ToolchainIdentity { "compiler-one" }) {
            let base = try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            let sandbox = try await ManifestCache.inputs(packageDir: package, disableSandbox: true)
            let environment = try await Environment.withManifestEnvironment(["FEATURE": "different"]) {
                try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            }
            let toolchain = try await ManifestCache.$toolchain.withValue(ManifestCache.ToolchainIdentity { "compiler-two" }) {
                try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            }
            let mirrorPath = package.appendingPathComponent(".swiftpm/configuration/mirrors.json")
            try await writeMirrorsConfiguration(["example.one": "example.two"], to: mirrorPath)
            let mirrors = try await ManifestCache.inputs(packageDir: package, disableSandbox: false)
            #expect(base != sandbox)
            #expect(base != environment)
            #expect(base != toolchain)
            #expect(base != mirrors)
        }
    }

    @Test(.inTemporaryDirectory)
    func retargetingAManifestSymlinkInvalidatesIdenticalContents() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let first = root.appendingPathComponent("First")
        let second = root.appendingPathComponent("Second")
        try await writeMinimalPackageManifest(at: first, name: "Same")
        try await writeMinimalPackageManifest(at: second, name: "Same")
        let manifest = root.appendingPathComponent("Package.swift")
        try await ManifestCache.$toolchain.withValue(ManifestCache.ToolchainIdentity { "compiler" }) {
            try await fileSystem.createSymbolicLink(
                from: manifest.absolutePath,
                to: first.appendingPathComponent("Package.swift").absolutePath
            )
            let before = try await ManifestCache.inputs(packageDir: root, disableSandbox: false)
            try await fileSystem.removePath(manifest)
            try await fileSystem.createSymbolicLink(
                from: manifest.absolutePath,
                to: second.appendingPathComponent("Package.swift").absolutePath
            )
            let after = try await ManifestCache.inputs(packageDir: root, disableSandbox: false)
            #expect(before != after)
        }
    }

    @Test(.inTemporaryDirectory)
    func missingLegacyCorruptAndMismatchedRecordsAreMisses() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        let cache = package.appendingPathComponent("dump.json")
        let output = Data("{}".utf8)
        #expect(await ManifestCache.read(at: cache, inputs: "inputs") == nil)
        try await fileSystem.atomicWrite(output, to: cache)
        try await fileSystem.atomicWrite("legacy fingerprint", to: cache.appendingPathExtension("envhash"))
        #expect(await ManifestCache.read(at: cache, inputs: "inputs") == nil)
        try await ManifestCache.write(output, at: cache, inputs: "inputs")
        #expect(try await fileSystem
            .exists(ManifestEnvironmentFingerprint.sidecarPath(forCacheFile: cache.absolutePath)) == false)
        #expect(await ManifestCache.read(at: cache, inputs: "inputs") == output)
        #expect(await ManifestCache.read(at: cache, inputs: "changed") == nil)
        try await fileSystem.atomicWrite("different output", to: cache)
        #expect(await ManifestCache.read(at: cache, inputs: "inputs") == nil)
        try await fileSystem.atomicWrite("interrupted sidecar", to: ManifestCache.sidecar(cache))
        #expect(await ManifestCache.read(at: cache, inputs: "inputs") == nil)
    }

    @Test(.inTemporaryDirectory)
    func uncacheableInputsStillProducePackageInfoWithoutCertifyingIt() async throws {
        let package = try #require(FileSystem.temporaryTestDirectory).fileURL
        try await writeMinimalPackageManifest(at: package, name: "Root")
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: nil) {
            let scratch = package.appendingPathComponent(".build")
            try await writePackageInfo(package: package, scratch: scratch)
            let packageInfo = scratch.appendingPathComponent("swifterpm/package-info/root.json")
            #expect(try await fileSystem.exists(ManifestCache.sidecar(packageInfo).absolutePath))

            // SwiftPM ignores this future candidate, but it cannot be read as manifest
            // source bytes. Cache validation must fall back to evaluation, not fail installation.
            try await fileSystem.makeDirectory(at: package.appendingPathComponent("Package@swift-99.0.swift").absolutePath)
            try await writePackageInfo(package: package, scratch: scratch)
            let data = try await fileSystem.readFile(at: packageInfo.absolutePath)
            #expect(ManifestParser.packageName(try JSONSerialization.jsonObject(with: data)) == "Root")
            #expect(try await fileSystem.exists(ManifestCache.sidecar(packageInfo).absolutePath) == false)
        }
    }

    @Test(.inTemporaryDirectory)
    func localManifestCacheSurvivesReplacementOfLocalCheckout() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let package = root.appendingPathComponent("Root")
        let local = root.appendingPathComponent("Local")
        let scratch = root.appendingPathComponent("RetainedScratch")
        try await writeMinimalPackageManifest(at: package, name: "Root")
        try await writeMinimalPackageManifest(at: local, name: "Local")
        try await fileSystem.atomicWrite(
            """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "Root", dependencies: [.package(path: "../Local")])
            """,
            to: package.appendingPathComponent("Package.swift")
        )
        let rootManifest: [String: Any] = [
            "dependencies": [["fileSystem": [["identity": "local", "path": local.path]]]],
        ]
        try await ManifestCache.withContext(packageDirectory: package, scratchDirectory: scratch) {
            let first = try await ManifestFileSystemDependencyGraph.collect(
                rootPackageDir: package, rootManifest: rootManifest, disableSandbox: true
            )
            #expect(first.count == 1)
            let cache = ManifestLoader.localCacheFilePath(rootPackageDir: package, packageDir: local)
            #expect(cache.path.hasPrefix(scratch.path + "/"))
            let before = try await fileSystem.fileMetadata(at: cache.absolutePath)?.lastModificationDate
            try await fileSystem.remove(local.absolutePath)
            try await writeMinimalPackageManifest(at: local, name: "Local")
            let sources = try await Cache(root: root.appendingPathComponent("sources"))
            let resolved = ResolvedPins(originHash: nil, pins: [], version: 3)
            try await WorkspaceRestorer.restorePackage(
                scratchDir: scratch, packageDir: package, cache: sources,
                registryConfig: RegistryConfig(), mirrors: MirrorConfig(), resolved: resolved,
                progress: nil, disableSandbox: true
            )
            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package, scratchDir: scratch, mirrors: MirrorConfig(),
                resolved: resolved, disableSandbox: true
            )
            #expect(try await fileSystem.exists(ManifestLoader.legacyCacheFilePath(packageDir: local).absolutePath) == false)
            let second = try await ManifestFileSystemDependencyGraph.collect(
                rootPackageDir: package, rootManifest: rootManifest, disableSandbox: true
            )
            #expect(second.count == 1)
            #expect(try await fileSystem.fileMetadata(at: cache.absolutePath)?.lastModificationDate == before)
            try await writeMinimalPackageManifest(at: local, name: "ChangedLocal")
            let changed = try await ManifestFileSystemDependencyGraph.collect(
                rootPackageDir: package, rootManifest: rootManifest, disableSandbox: true
            )
            #expect(ManifestParser.packageName(changed[0].manifest) == "ChangedLocal")
        }
    }

    @Test(.inTemporaryDirectory, arguments: [SwifterPMCachedDirectoryMaterialization.symlink, .copy])
    func registryMaterializationPreservesCachedDumps(mode: SwifterPMCachedDirectoryMaterialization) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let source = root.appendingPathComponent("sources/dependency")
        let scratch = root.appendingPathComponent("scratch")
        let download = scratch.appendingPathComponent("registry/downloads/example/dependency/1.0.0")
        try await writeMinimalPackageManifest(at: source, name: "Dependency")
        try await ManifestCache.withContext(packageDirectory: root, scratchDirectory: scratch) {
            try await Environment.withCachedDirectoryMaterialization(mode) {
                try await fileSystem.replaceWithRegistryDownloadDirectory(source: source, destination: download)
                let first = try await ManifestLoader.dumpPackageJSON(packageDir: download, disableSandbox: true)
                let cache = ManifestLoader.cacheFilePath(packageDir: download)
                #expect(cache.path.hasPrefix(scratch.appendingPathComponent("swifterpm/manifests").path))
                let before = try await fileSystem.fileMetadata(at: cache.absolutePath)?.lastModificationDate

                try await fileSystem.replaceWithRegistryDownloadDirectory(source: source, destination: download)
                let second = try await ManifestLoader.dumpPackageJSON(packageDir: download, disableSandbox: true)
                #expect(second == first)
                #expect(try await fileSystem.fileMetadata(at: cache.absolutePath)?.lastModificationDate == before)

                try await writeMinimalPackageManifest(at: source, name: "ChangedDependency")
                try await fileSystem.replaceWithRegistryDownloadDirectory(source: source, destination: download)
                let changed = try await ManifestLoader.dumpPackage(packageDir: download, disableSandbox: true)
                #expect(ManifestParser.packageName(changed) == "ChangedDependency")
            }
        }
    }

    private func writePackageInfo(package: URL, scratch: URL) async throws {
        try await PackageInfoCacheWriter.write(
            packageDir: package, scratchDir: scratch,
            resolved: ResolvedPins(originHash: nil, pins: [], version: 3),
            mirrors: MirrorConfig(), cacheDir: nil, disableSandbox: true, quiet: true
        )
    }
}
