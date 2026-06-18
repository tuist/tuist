import Foundation
import Testing
@testable import SwifterPMCore

struct CLITests {
    @Test
    func resolveParsesGlobalAndCommandOptions() throws {
        let cli = try CLIParser.parse([
            "--package-path", "/tmp/package",
            "--cache-path", "/tmp/cache",
            "--scratch-path", "/tmp/scratch",
            "--disable-sandbox",
            "--default-registry-url", "https://registry.example.com",
            "--cached-directory-materialization", "symlink",
            "-q",
            "resolve",
            "--package-dir", "/tmp/command-package",
            "--cache-dir", "/tmp/command-cache",
            "--write",
            "--print-only",
        ])

        #expect(cli.packagePath?.path == "/tmp/package")
        #expect(cli.cachePath?.path == "/tmp/cache")
        #expect(cli.scratchPath?.path == "/tmp/scratch")
        #expect(cli.disableSandbox)
        #expect(cli.quiet)
        #expect(cli.defaultRegistryURL == "https://registry.example.com")
        #expect(cli.cachedDirectoryMaterialization == .symlink)

        guard case .resolve(let options) = cli.command else {
            Issue.record("expected resolve command")
            return
        }
        #expect(options.packageDir.path == "/tmp/command-package")
        #expect(options.cacheDir?.path == "/tmp/command-cache")
        #expect(options.write)
        #expect(!options.restore)
        #expect(options.printOnly)
    }

    @Test
    func updateParsesPackageNamesAndFlags() throws {
        let cli = try CLIParser.parse([
            "--skip-update",
            "update",
            "foo",
            "bar",
            "--restore",
        ])

        #expect(cli.skipUpdate)
        guard case .update(let options) = cli.command else {
            Issue.record("expected update command")
            return
        }
        #expect(options.packageNames == ["foo", "bar"])
        #expect(options.restore)
    }

    @Test
    func restoreParsesDirectoryOptions() throws {
        let cli = try CLIParser.parse([
            "--build-path", "/tmp/build",
            "restore",
            "--package-dir", "/tmp/package",
            "--cache-dir", "/tmp/cache",
            "--scratch-dir", "/tmp/scratch",
        ])

        #expect(cli.buildPath?.path == "/tmp/build")
        guard case .restore(let options) = cli.command else {
            Issue.record("expected restore command")
            return
        }
        #expect(options.packageDir.path == "/tmp/package")
        #expect(options.cacheDir?.path == "/tmp/cache")
        #expect(options.scratchDir?.path == "/tmp/scratch")
    }

    @Test
    func pathResolverResolvesRelativePathsAgainstChdirWithoutChangingProcessDirectory()
        async throws
    {
        try await withTemporaryDirectory { root in
            let workspace = root.appendingPathComponent("workspace")
            try await fileSystem.makeDirectory(at: workspace.absolutePath, options: [.createTargetParentDirectories])

            let originalDirectory = try await fileSystem.currentWorkingDirectory().pathString
            let cli = try CLIParser.parse([
                "--chdir", workspace.path,
                "restore",
                "--package-dir", "Package",
            ])
            guard case .restore(let options) = cli.command else {
                Issue.record("expected restore command")
                return
            }
            let resolver = try await CLIPathResolver(chdir: cli.chdir)
            let resolvedWorkspace = workspace.standardizedFileURL

            #expect(resolver.baseDirectory.path == resolvedWorkspace.path)
            #expect(
                resolver.resolve(options.packageDir).path
                    == resolvedWorkspace.appendingPathComponent("Package").path)
            #expect(resolver.resolve(CLIPath("/tmp/cache")).path == "/tmp/cache")
            #expect(try await fileSystem.currentWorkingDirectory().pathString == originalDirectory)
        }
    }

    @Test
    func pathResolverRejectsMissingChdir() async throws {
        try await withTemporaryDirectory { root in
            let missing = root.appendingPathComponent("missing")

            await #expect(throws: (any Error).self) {
                try await CLIPathResolver(chdir: CLIPath(missing.path))
            }
        }
    }

    @Test
    func commandSpecificUnknownOptionsAreRejected() {
        #expect(throws: (any Error).self) {
            try CLIParser.parse(["resolve", "--unknown-option"])
        }
    }

    @Test
    func publicCommandParserBuildsResolutionRequestFromResolveArguments() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let cache = root.appendingPathComponent("Cache")
            let scratch = root.appendingPathComponent("Scratch")
            let config = root.appendingPathComponent("registries.json")
            let packageInfoCache = root.appendingPathComponent("PackageInfo")

            let command = try await SwifterPMCommandParser.parse([
                "--package-path", package.path,
                "--cache-path", cache.path,
                "--scratch-path", scratch.path,
                "--config-path", config.path,
                "--default-registry-url", "https://registry.example.com",
                "--disable-sandbox",
                "--force-resolved-versions",
                "--skip-update",
                "--replace-scm-with-registry",
                "--package-info-cache-path", packageInfoCache.path,
                "--cached-directory-materialization", "symlink",
                "--quiet",
                "resolve",
            ])

            guard case .resolve(let request) = command else {
                Issue.record("expected resolve command")
                return
            }
            #expect(request.packageDirectory == package.standardizedFileURL)
            #expect(request.cacheDirectory == cache.standardizedFileURL)
            #expect(request.scratchDirectory == scratch.standardizedFileURL)
            #expect(request.registryConfigurationPath == config.standardizedFileURL)
            #expect(request.defaultRegistryURL == "https://registry.example.com")
            #expect(request.disableSandbox)
            #expect(request.forceResolvedVersions)
            #expect(request.skipUpdate)
            #expect(request.writeResolvedFile)
            #expect(request.restorePackage)
            #expect(request.disablePackageInfoCache == false)
            #expect(request.packageInfoCacheDirectory == packageInfoCache.standardizedFileURL)
            #expect(request.scmToRegistryTransformation == .replaceSCMWithRegistry)
            #expect(request.cachedDirectoryMaterialization == .symlink)
            #expect(request.quiet)
        }
    }

    @Test
    func publicCommandParserBuildsUpdateRequestFromUpdateArguments() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let build = root.appendingPathComponent("Build")

            let command = try await SwifterPMCommandParser.parse([
                "--package-path", package.path,
                "--build-path", build.path,
                "--disable-automatic-resolution",
                "--use-registry-identity-for-scm",
                "update",
            ])

            guard case .update(let request) = command else {
                Issue.record("expected update command")
                return
            }
            #expect(request.packageDirectory == package.standardizedFileURL)
            #expect(request.scratchDirectory == build.standardizedFileURL)
            #expect(request.forceResolvedVersions)
            #expect(request.scmToRegistryTransformation == .useRegistryIdentityForSCM)
        }
    }

    @Test
    func publicCommandParserBuildsRestoreRequestFromRestoreArguments() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let cache = root.appendingPathComponent("Cache")
            let scratch = root.appendingPathComponent("Scratch")

            let command = try await SwifterPMCommandParser.parse([
                "restore",
                "--package-dir", package.path,
                "--cache-dir", cache.path,
                "--scratch-dir", scratch.path,
            ])

            guard case .restore(let request) = command else {
                Issue.record("expected restore command")
                return
            }
            #expect(request.packageDirectory == package.standardizedFileURL)
            #expect(request.cacheDirectory == cache.standardizedFileURL)
            #expect(request.scratchDirectory == scratch.standardizedFileURL)
        }
    }

    @Test
    func parserRejectsInvalidCachedDirectoryMaterialization() {
        do {
            _ = try CLIParser.parse([
                "--cached-directory-materialization", "hardlink",
                "restore",
            ])
            Issue.record("expected parse to fail")
        } catch {
            let message = SwifterPMCommand.message(for: error)
            #expect(message.contains("automatic"))
            #expect(message.contains("copy"))
            #expect(message.contains("symlink"))
        }
    }

    @Test
    func publicCommandParserRejectsConflictingRegistryTransformationFlags() async {
        await #expect(throws: (any Error).self) {
            try await SwifterPMCommandParser.parse([
                "--replace-scm-with-registry",
                "--use-registry-identity-for-scm",
                "resolve",
            ])
        }
    }
}
