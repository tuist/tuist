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

    @Test
    func coldResolutionSeedsTheSwifterPMSourceCache() async throws {
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tags: ["1.0.0"])

            let package = root.appendingPathComponent("App")
            try await writeAppPackageManifest(at: package, dependencyURL: dependency.path)
            let cacheDirectory = root.appendingPathComponent("cache")
            let cache = try await Cache(root: cacheDirectory)

            let result = try await SwifterPM().resolve(
                .init(
                    packageDirectory: package,
                    cacheDirectory: cacheDirectory,
                    scratchDirectory: root.appendingPathComponent("scratch"),
                    disableSandbox: true,
                    quiet: true
                ))

            #expect(result.pins.map(\.identity) == ["dependency"])
            #expect(try await cache.hasCachedSources())
            #expect(
                try await !PackageResolver.shouldUseNativeColdPath(
                    packageDir: package,
                    cacheRoot: cache.root
                )
            )

            let pin = try #require(
                try await ResolvedFile.read(packageDir: package).pins.first
            )
            let cachedSource = try cache.sourcePath(pin: pin)
            try await fileSystem.atomicWrite(
                "cached\n",
                to: cachedSource.appendingPathComponent(".swifterpm-cache-marker")
            )

            let freshScratch = root.appendingPathComponent("fresh-scratch")
            let warmResult = try await SwifterPM().resolve(
                .init(
                    packageDirectory: package,
                    cacheDirectory: cacheDirectory,
                    scratchDirectory: freshScratch,
                    disableSandbox: true,
                    quiet: true
                ))

            #expect(warmResult.pins.map(\.identity) == ["dependency"])
            #expect(
                try await fileSystem.exists(
                    freshScratch
                        .appendingPathComponent("checkouts")
                        .appendingPathComponent(PinKind.checkoutDirectoryName(pin))
                        .appendingPathComponent(".swifterpm-cache-marker")
                        .absolutePath
                )
            )
        }
    }

    @Test
    func coldResolutionCopiesCheckoutsInContinuousIntegration() async throws {
        try await Environment.$values.withValue(["CI": "1"]) {
            try await withTemporaryDirectory { root in
                let dependency = root.appendingPathComponent("Dependency")
                try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
                try await initGitDependency(at: dependency, tags: ["1.0.0"])

                let package = root.appendingPathComponent("App")
                try await writeAppPackageManifest(at: package, dependencyURL: dependency.path)
                let cacheDirectory = root.appendingPathComponent("cache")
                let scratch = root.appendingPathComponent("scratch")

                let result = try await SwifterPM().resolve(
                    .init(
                        packageDirectory: package,
                        cacheDirectory: cacheDirectory,
                        scratchDirectory: scratch,
                        disableSandbox: true,
                        quiet: true
                    ))

                #expect(result.pins.map(\.identity) == ["dependency"])
                let pin = try #require(
                    try await ResolvedFile.read(packageDir: package).pins.first
                )
                let checkout = scratch
                    .appendingPathComponent("checkouts")
                    .appendingPathComponent(PinKind.checkoutDirectoryName(pin))
                #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
                #expect(try await fileSystem.exists(checkout.appendingPathComponent("Package.swift").absolutePath))

                try await fileSystem.remove(cacheDirectory.absolutePath)
                #expect(try await fileSystem.exists(checkout.appendingPathComponent("Package.swift").absolutePath))
            }
        }
    }

    @Test
    func coldResolutionRepairsDanglingCheckoutsInContinuousIntegration() async throws {
        try await withTemporaryDirectory { root in
            let dependency = root.appendingPathComponent("Dependency")
            try await writeLibraryPackageManifest(at: dependency, name: "Dependency")
            try await initGitDependency(at: dependency, tags: ["1.0.0"])

            let package = root.appendingPathComponent("App")
            try await writeAppPackageManifest(at: package, dependencyURL: dependency.path)
            let cacheDirectory = root.appendingPathComponent("cache")
            let scratch = root.appendingPathComponent("scratch")

            try await Environment.withCachedDirectoryMaterialization(.symlink) {
                _ = try await SwifterPM().resolve(
                    .init(
                        packageDirectory: package,
                        cacheDirectory: cacheDirectory,
                        scratchDirectory: scratch,
                        disableSandbox: true,
                        quiet: true
                    ))
            }

            let pin = try #require(
                try await ResolvedFile.read(packageDir: package).pins.first
            )
            let checkout = scratch
                .appendingPathComponent("checkouts")
                .appendingPathComponent(PinKind.checkoutDirectoryName(pin))
            let cache = try await Cache(root: cacheDirectory)
            try await fileSystem.remove((try cache.sourcePath(pin: pin)).absolutePath)

            try await Environment.$values.withValue(["CI": "1"]) {
                _ = try await SwifterPM().resolve(
                    .init(
                        packageDirectory: package,
                        cacheDirectory: cacheDirectory,
                        scratchDirectory: scratch,
                        disableSandbox: true,
                        quiet: true
                    ))
            }

            #expect(fileSystem.isDirectoryAndNotSymlink(checkout))
            #expect(try await fileSystem.exists(checkout.appendingPathComponent("Package.swift").absolutePath))
        }
    }

    @Test
    func nativeColdPathIsUsedWhenTheSharedCacheOnlyContainsOtherPackages() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("App")
            try await writeMinimalPackageManifest(at: package, name: "App")
            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let cachedPin = ResolvedPin(
                identity: "cached",
                kind: "remoteSourceControl",
                location: "https://example.com/cached.git",
                state: .init(branch: nil, revision: "aaaaaaaa", version: "1.0.0")
            )
            let missingPin = ResolvedPin(
                identity: "missing",
                kind: "remoteSourceControl",
                location: "https://example.com/missing.git",
                state: .init(branch: nil, revision: "bbbbbbbb", version: "1.0.0")
            )
            let cachedSource = try cache.sourcePath(pin: cachedPin)
            try await fileSystem.makeDirectory(
                at: cachedSource.absolutePath,
                options: [.createTargetParentDirectories]
            )
            try await writeMinimalPackageManifest(at: cachedSource, name: "Cached")
            try await ResolvedFile.write(
                packageDir: package,
                resolved: .init(originHash: "origin", pins: [missingPin], version: 3)
            )

            #expect(
                try await PackageResolver.shouldUseNativeColdPath(
                    packageDir: package,
                    cacheRoot: cache.root
                )
            )
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
