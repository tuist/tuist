import Foundation
import Testing
@testable import SwifterPMCore

struct ResolveTests {
    @Test
    func defaultResolverShellsOutToSwiftPMWithoutWritingWhenRequested() async throws {
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tags: ["1.0.0"])

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
    func resolutionSurvivesSwiftPMFailingToFetchABinaryArtifact() async throws {
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tags: ["1.0.0"])

            let package = root.appendingPathComponent("App")
            try await writeAppPackageManifest(
                at: package,
                dependencyURL: dependency.path,
                // Unroutable, so SwiftPM's artifact stage always fails while version solving,
                // which is the only stage swifterpm needs from it, still succeeds.
                binaryArtifactURL: "https://127.0.0.1:1/Artifact.xcframework.zip"
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
        }
    }

    @Test
    func binaryArtifactFailuresAreTheOnlySwiftPMFailuresResolutionIgnores() {
        let collision = """
        Downloading binary artifact https://example.com/Artifact.xcframework.zip
        error: failed downloading 'https://example.com/Artifact.xcframework.zip' which is \
        required by binary target 'Artifact': /cache/artifacts/https___example_com already \
        exists in file system
        error: fatalError
        """
        #expect(PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: collision)))

        let checksum = """
        error: checksum of downloaded artifact of binary target 'Artifact' (abc) does not \
        match checksum specified by the manifest (def)
        """
        #expect(PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: checksum)))

        let transport = """
        error: failed downloading 'https://example.com/Artifact.xcframework.zip' which is \
        required by binary target 'Artifact': The request timed out.
        """
        #expect(PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: transport)))

        let unresolvable = """
        error: Dependencies could not be resolved because no versions of 'dependency' match \
        the requirement 9.9.9..<10.0.0.
        """
        #expect(!PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: unresolvable)))

        // A manifest that merely mentions a binary target is still a resolution failure.
        let manifest = """
        error: invalid URL scheme for binary target 'Artifact'; valid schemes are: 'https'
        """
        #expect(!PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: manifest)))

        #expect(!PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: collision + "\n" + unresolvable)))
        #expect(!PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: "")))
        #expect(!PackageResolver.failedOnlyOnBinaryArtifacts(outcome(stderr: "error: fatalError")))
    }

    private func outcome(stderr: String) -> SystemProcess.Outcome {
        SystemProcess.Outcome(
            succeeded: false,
            terminationStatusDescription: "exited(1)",
            stdout: Data(),
            stderr: Data(stderr.utf8)
        )
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
    func resolveOrLoadReturnsEmptyPinsWhenReadOnlyAndPackageResolvedIsMissing() async throws {
        // A missing Package.resolved under --force-resolved-versions is the
        // normal shape of an all-local package graph: there are no versioned pins
        // to force, and SwiftPM's own `swift package resolve
        // --force-resolved-versions` succeeds as a no-op there and writes no
        // lockfile. resolveOrLoad matches that with an empty pin set rather than
        // erroring. A graph that genuinely needs a lockfile (unpinned remote
        // dependencies) still fails, because `assertResolvedFileUpToDate`
        // delegates the check back to SwiftPM once the checkouts are materialized.
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let resolved = try await PackageResolver.resolveOrLoad(
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
            #expect(resolved.pins.isEmpty)
        }
    }

    @Test
    func forceResolvedVersionsRejectsAnOutOfDateLockfileViaSwiftPM() async throws {
        // The readOnly path restores the pins verbatim; out-of-date detection is
        // delegated to `swift package resolve --force-resolved-versions` rather
        // than reimplementing SwiftPM's resolver precomputation. Bumping the
        // manifest past the committed pin must surface SwiftPM's out-of-date
        // error, while an in-sync lockfile must pass.
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tags: ["1.0.0", "2.0.0"])

            let package = root.appendingPathComponent("App")
            try await writeAppPackageManifest(
                at: package, dependencyURL: dependency.path, exactVersion: "1.0.0"
            )

            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let scratch = root.appendingPathComponent("scratch")
            _ = try await PackageResolver.resolve(
                packageDir: package,
                scratchDir: scratch,
                cache: cache,
                registryConfig: RegistryConfig(),
                disableSandbox: true,
                writeResolvedFile: true
            )

            // In sync: the pinned 1.0.0 satisfies the manifest, so the check passes.
            try await PackageResolver.assertResolvedFileUpToDate(
                packageDir: package,
                scratchDir: scratch,
                cacheDir: cache.root,
                registryConfigurationPath: nil,
                defaultRegistryURL: nil,
                disableSandbox: true,
                scmToRegistryTransformation: .disabled
            )

            // Bump the manifest past the lockfile: SwiftPM rejects the stale pin.
            try await writeAppPackageManifest(
                at: package, dependencyURL: dependency.path, exactVersion: "2.0.0"
            )
            await #expect(throws: ToolError.self) {
                try await PackageResolver.assertResolvedFileUpToDate(
                    packageDir: package,
                    scratchDir: scratch,
                    cacheDir: cache.root,
                    registryConfigurationPath: nil,
                    defaultRegistryURL: nil,
                    disableSandbox: true,
                    scmToRegistryTransformation: .disabled
                )
            }
        }
    }

    private func initGitDependency(at dependency: URL, tags: [String]) async throws {
        try await SystemProcess.run("git", ["init"], workingDirectory: dependency)
        try await SystemProcess.run(
            "git", ["config", "user.name", "SwifterPM Tests"], workingDirectory: dependency)
        try await SystemProcess.run(
            "git", ["config", "user.email", "tests@example.com"], workingDirectory: dependency)
        try await SystemProcess.run(
            "git", ["add", "Package.swift", "Sources"], workingDirectory: dependency)
        try await SystemProcess.run("git", ["commit", "-m", "Initial"], workingDirectory: dependency)
        for tag in tags {
            try await SystemProcess.run("git", ["tag", tag], workingDirectory: dependency)
        }
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
        exactVersion: String = "1.0.0",
        binaryArtifactURL: String? = nil
    ) async throws {
        try await fileSystem.makeDirectory(
            at: packageDir.appendingPathComponent("Sources/App").absolutePath,
            options: [.createTargetParentDirectories]
        )
        let binaryTarget =
            binaryArtifactURL.map {
                """
                        .binaryTarget(
                            name: "Artifact",
                            url: "\($0)",
                            checksum: "\(String(repeating: "0", count: 64))"
                        ),

                """
            } ?? ""
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
            \(binaryTarget)        .target(name: "App", dependencies: [
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
