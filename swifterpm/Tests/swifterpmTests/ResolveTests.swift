import Foundation
import Testing
@testable import SwifterPMCore

struct ResolveTests {
    @Test
    func defaultResolverShellsOutToSwiftPMWithoutWritingWhenRequested() async throws {
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tag: "1.0.0")

            let package = root.appendingPathComponent("App")
            try await writeAppPackageManifest(
                at: package,
                dependencyURL: dependency.path
            )

            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let resolved = try await PackageResolver.resolve(
                packageDir: package,
                scratchDir: root.appendingPathComponent("scratch"),
                cache: cache,
                registryConfig: RegistryConfig(),
                disableSandbox: true,
                writeResolvedFile: false
            )

            let pin = try #require(resolved.pins.first)
            #expect(pin.identity == "dependency")
            #expect(pin.state.version == "1.0.0")
            let packageResolvedExists = try await fileSystem.exists(
                package.appendingPathComponent("Package.resolved").absolutePath
            )
            #expect(!packageResolvedExists)
        }
    }

    @Test
    func localSourceControlPackageLocationRequiresPackageManifest() async throws {
        try await withTemporaryDirectory { root in
            #expect(try await PackageResolver.localSourceControlPackageLocation(root.path) == nil)
            try await fileSystem.atomicWrite(
                "package manifest\n", to: root.appendingPathComponent("Package.swift"))

            #expect(
                try await PackageResolver.localSourceControlPackageLocation(root.path)?.path
                    == root.path)
            #expect(
                try await PackageResolver.sourceControlKind(location: root.path)
                    == "localSourceControl")
            #expect(
                try await PackageResolver.sourceControlKind(
                    location: "https://github.com/example/foo")
                    == "remoteSourceControl")
        }
    }

    @Test
    func localSourceControlPackageLocationAcceptsFileURLs() async throws {
        try await withTemporaryDirectory { root in
            try await fileSystem.atomicWrite(
                "package manifest\n", to: root.appendingPathComponent("Package.swift"))

            #expect(
                try await PackageResolver.localSourceControlPackageLocation(root.absoluteString)?
                    .path
                    == root.path)
        }
    }

    @Test
    func resolveOrLoadReportsAClearErrorWhenReadOnlyAndPackageResolvedIsMissing() async throws {
        // Pre-PR the readOnly branch fell into `ResolvedFile.read`, which
        // surfaced a low-level `no such file` from the filesystem layer with no
        // hint that --force-resolved-versions was the cause. Verify the
        // domain-specific error replaces it.
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            await #expect(throws: ToolError.self) {
                try await PackageResolver.resolveOrLoad(
                    packageDir: root,
                    cache: cache,
                    registryConfig: RegistryConfig(),
                    disableSandbox: true,
                    scmToRegistryTransformation: .disabled,
                    preferResolvedFile: true,
                    readOnly: true,
                    skipUpdate: false,
                    writeResolvedFile: false,
                    progress: nil
                )
            }
        }
    }

    @Test
    func resolveOrLoadReadOnlyFailsWhenAPinNoLongerSatisfiesTheManifest() async throws {
        // Pre-PR the readOnly branch read Package.resolved verbatim with no
        // manifest check, so a manifest bumped past its lockfile (here an
        // `exact:` raised from 1.0.0 to 2.0.0 without re-resolving) was restored
        // to the stale 1.0.0 and reported success — where pure SwiftPM
        // `swift package resolve --force-resolved-versions` errors out-of-date.
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tag: "1.0.0")

            let package = root.appendingPathComponent("App")
            try await writeAppPackageManifest(
                at: package, dependencyURL: dependency.path, exactVersion: "1.0.0"
            )

            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            _ = try await PackageResolver.resolve(
                packageDir: package,
                scratchDir: root.appendingPathComponent("scratch"),
                cache: cache,
                registryConfig: RegistryConfig(),
                disableSandbox: true,
                writeResolvedFile: true
            )

            // Bump the manifest past the lockfile; clear the manifest dump cache
            // so the readOnly validation re-reads the changed requirement rather
            // than a same-second mtime-stale cache.
            try await writeAppPackageManifest(
                at: package, dependencyURL: dependency.path, exactVersion: "2.0.0"
            )
            try? await fileSystem.removePath(ManifestLoader.cacheFilePath(packageDir: package))

            await #expect(throws: ToolError.self) {
                try await PackageResolver.resolveOrLoad(
                    packageDir: package,
                    scratchDir: root.appendingPathComponent("scratch"),
                    cache: cache,
                    registryConfig: RegistryConfig(),
                    disableSandbox: true,
                    scmToRegistryTransformation: .disabled,
                    preferResolvedFile: true,
                    readOnly: true,
                    skipUpdate: false,
                    writeResolvedFile: false,
                    progress: nil
                )
            }
        }
    }

    @Test
    func resolveOrLoadReadOnlyReturnsPinsWhenTheyStillSatisfyTheManifest() async throws {
        // Guard against a false positive: an in-sync lockfile must still load in
        // readOnly mode without re-resolving.
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tag: "1.0.0")

            let package = root.appendingPathComponent("App")
            try await writeAppPackageManifest(
                at: package, dependencyURL: dependency.path, exactVersion: "1.0.0"
            )

            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            _ = try await PackageResolver.resolve(
                packageDir: package,
                scratchDir: root.appendingPathComponent("scratch"),
                cache: cache,
                registryConfig: RegistryConfig(),
                disableSandbox: true,
                writeResolvedFile: true
            )

            let resolved = try await PackageResolver.resolveOrLoad(
                packageDir: package,
                scratchDir: root.appendingPathComponent("scratch"),
                cache: cache,
                registryConfig: RegistryConfig(),
                disableSandbox: true,
                scmToRegistryTransformation: .disabled,
                preferResolvedFile: true,
                readOnly: true,
                skipUpdate: false,
                writeResolvedFile: false,
                progress: nil
            )

            let pin = try #require(resolved.pins.first { $0.identity == "dependency" })
            #expect(pin.state.version == "1.0.0")
        }
    }

    @Test
    func validateResolvedGraphFailsWhenATransitivePinViolatesAnIntermediateManifest() async throws {
        // Closes the gap with SwiftPM's whole-graph precomputation: the root
        // manifest is in sync (root -> A exact 1.0.0, pinned 1.0.0) but A's own
        // manifest requires B exact 2.0.0 while Package.resolved pins B at 1.0.0.
        // The direct-only check can't see this; the graph walk must.
        try await withTemporaryDirectory { root in
            let scratch = root.appendingPathComponent(".build")
            try await writeManifestWithExactDependency(
                at: root, name: "Root",
                dependencyURL: "https://example.com/A.git", dependencyPackage: "A", exactVersion: "1.0.0"
            )
            try await writeManifestWithExactDependency(
                at: scratch.appendingPathComponent("checkouts/A"), name: "A",
                dependencyURL: "https://example.com/B.git", dependencyPackage: "B", exactVersion: "2.0.0"
            )

            let resolved = ResolvedPins(
                originHash: nil,
                pins: [
                    ResolvedPin(
                        identity: "a", kind: "remoteSourceControl", location: "https://example.com/A.git",
                        state: ResolvedState(branch: nil, revision: "a000", version: "1.0.0")
                    ),
                    ResolvedPin(
                        identity: "b", kind: "remoteSourceControl", location: "https://example.com/B.git",
                        state: ResolvedState(branch: nil, revision: "b000", version: "1.0.0")
                    ),
                ],
                version: 3
            )

            await #expect(throws: ToolError.self) {
                try await PackageResolver.validateResolvedGraphSatisfiesManifests(
                    packageDir: root, scratchDir: scratch, resolved: resolved, disableSandbox: true
                )
            }
        }
    }

    @Test
    func validateResolvedGraphAcceptsAnInSyncTransitiveGraph() async throws {
        // Guard against a false positive: the same graph with B pinned at the
        // 2.0.0 that A requires must validate cleanly.
        try await withTemporaryDirectory { root in
            let scratch = root.appendingPathComponent(".build")
            try await writeManifestWithExactDependency(
                at: root, name: "Root",
                dependencyURL: "https://example.com/A.git", dependencyPackage: "A", exactVersion: "1.0.0"
            )
            try await writeManifestWithExactDependency(
                at: scratch.appendingPathComponent("checkouts/A"), name: "A",
                dependencyURL: "https://example.com/B.git", dependencyPackage: "B", exactVersion: "2.0.0"
            )

            let resolved = ResolvedPins(
                originHash: nil,
                pins: [
                    ResolvedPin(
                        identity: "a", kind: "remoteSourceControl", location: "https://example.com/A.git",
                        state: ResolvedState(branch: nil, revision: "a000", version: "1.0.0")
                    ),
                    ResolvedPin(
                        identity: "b", kind: "remoteSourceControl", location: "https://example.com/B.git",
                        state: ResolvedState(branch: nil, revision: "b000", version: "2.0.0")
                    ),
                ],
                version: 3
            )

            try await PackageResolver.validateResolvedGraphSatisfiesManifests(
                packageDir: root, scratchDir: scratch, resolved: resolved, disableSandbox: true
            )
        }
    }

    private func writeManifestWithExactDependency(
        at packageDir: URL,
        name: String,
        dependencyURL: String,
        dependencyPackage: String,
        exactVersion: String
    ) async throws {
        try await fileSystem.makeDirectory(
            at: packageDir.appendingPathComponent("Sources/\(name)").absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await fileSystem.atomicWrite(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(name)",
                products: [
                    .library(name: "\(name)", targets: ["\(name)"]),
                ],
                dependencies: [
                    .package(url: "\(dependencyURL)", exact: "\(exactVersion)"),
                ],
                targets: [
                    .target(name: "\(name)", dependencies: [
                        .product(name: "\(dependencyPackage)", package: "\(dependencyPackage)"),
                    ]),
                ]
            )
            """,
            to: packageDir.appendingPathComponent("Package.swift")
        )
        try await fileSystem.atomicWrite(
            "public struct \(name) {}\n",
            to: packageDir.appendingPathComponent("Sources/\(name)/\(name).swift")
        )
    }

    private func initGitDependency(at dependency: URL, tag: String) async throws {
        try await SystemProcess.run("git", ["init"], workingDirectory: dependency)
        try await SystemProcess.run(
            "git", ["config", "user.name", "SwifterPM Tests"], workingDirectory: dependency)
        try await SystemProcess.run(
            "git", ["config", "user.email", "tests@example.com"], workingDirectory: dependency)
        try await SystemProcess.run(
            "git", ["add", "Package.swift", "Sources"], workingDirectory: dependency)
        try await SystemProcess.run("git", ["commit", "-m", "Initial"], workingDirectory: dependency)
        try await SystemProcess.run("git", ["tag", tag], workingDirectory: dependency)
    }

    private func writeLibraryPackageManifest(at packageDir: URL, name: String) async throws {
        try await fileSystem.makeDirectory(
            at: packageDir.appendingPathComponent("Sources/\(name)").absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await fileSystem.atomicWrite(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "\(name)",
                products: [
                    .library(name: "\(name)", targets: ["\(name)"]),
                ],
                targets: [
                    .target(name: "\(name)"),
                ]
            )
            """,
            to: packageDir.appendingPathComponent("Package.swift")
        )
        try await fileSystem.atomicWrite(
            "public struct \(name) {}\n",
            to: packageDir.appendingPathComponent("Sources/\(name)/\(name).swift")
        )
    }

    private func writeAppPackageManifest(
        at packageDir: URL,
        dependencyURL: String,
        exactVersion: String = "1.0.0"
    ) async throws {
        try await fileSystem.makeDirectory(
            at: packageDir.appendingPathComponent("Sources/App").absolutePath,
            options: [.createTargetParentDirectories]
        )
        try await fileSystem.atomicWrite(
            """
            // swift-tools-version: 6.0
            import PackageDescription

            let package = Package(
                name: "App",
                products: [
                    .library(name: "App", targets: ["App"]),
                ],
                dependencies: [
                    .package(url: "\(dependencyURL)", exact: "\(exactVersion)"),
                ],
                targets: [
                    .target(name: "App", dependencies: [
                        .product(name: "Dependency", package: "Dependency"),
                    ]),
                ]
            )
            """,
            to: packageDir.appendingPathComponent("Package.swift")
        )
        try await fileSystem.atomicWrite(
            "import Dependency\npublic struct App {}\n",
            to: packageDir.appendingPathComponent("Sources/App/App.swift")
        )
    }
}
