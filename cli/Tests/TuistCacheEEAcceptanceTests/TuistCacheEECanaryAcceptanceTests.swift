import FileSystem
import FileSystemTesting
import Foundation
import Logging
import Path
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistCache
import TuistCacheCommand
import TuistCAS
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGenerateCommand
import TuistLoggerTesting
import TuistNooraTesting
import TuistServer
import TuistSupport
import TuistTestCommand
import TuistTesting
import XcodeProj
@testable import TuistCacheEE
@testable import TuistKit

struct TuistCacheEECanaryAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_project_with_caching_enabled", accountHandle: "tuist")
    ) func generated_project_with_caching_enabled() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)

        let casPluginBuildDirectory = try casPluginBuildDirectory()
        let pluginPath = casPluginBuildDirectory.appending(component: "libtuist_cas_plugin.dylib")
        let proxyPath = casPluginBuildDirectory.appending(component: "tuist-cas-proxy")
        try #require(
            await fileSystem.exists(pluginPath),
            "The CAS plugin is missing. Build it with `mise run build` in `cas-plugin`."
        )
        try #require(
            await fileSystem.exists(proxyPath),
            "The cache proxy is missing. Build it with `mise run build` in `cas-plugin`."
        )
        // `ProjectMapperFactory` resolves the plugin from `Environment.current`, which is
        // mocked here and inherits only `PATH`.
        environment.variables["TUIST_CAS_PLUGIN_PATH"] = pluginPath.pathString

        try await withShortStateDirectory(fileSystem: fileSystem) { stateDirectory in
            let previousStateDirectory = environment.stateDirectory
            environment.stateDirectory = stateDirectory
            defer { environment.stateDirectory = previousStateDirectory }

            let fixtureFullHandle = try #require(TuistTest.fixtureFullHandle)

            try await fileSystem.writeText(
                """
                import ProjectDescription

                let tuist = Tuist(
                    fullHandle: "\(fixtureFullHandle)",
                    url: "\(Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")",
                    project: .tuist(
                        generationOptions: .options(
                            enableCaching: true
                        )
                    )
                )
                """,
                at: fixtureDirectory.appending(components: "Tuist.swift"),
                options: Set([.overwrite])
            )

            let proxySocketPath = environment.casProxySocketPath()
            try #require(
                proxySocketPath.pathString.utf8.count < 104,
                "Unix-domain socket path is too long: \(proxySocketPath.pathString)"
            )
            // The plugin reads this inside the compiler frontends, and
            // `XcodeBuildController` spawns xcodebuild with `Environment.current.variables`,
            // so setting it here is what makes the frontends address the proxy this test
            // starts instead of the machine-wide one.
            environment.variables["TUIST_CAS_PROXY_SOCKET"] = proxySocketPath.pathString

            try await withCacheProxy(
                executablePath: proxyPath,
                fullHandle: fixtureFullHandle,
                socketPath: proxySocketPath,
                fileSystem: fileSystem
            ) {
                try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
                resetUI()

                // No `COMPILATION_CACHE_REMOTE_SERVICE_PATH` override: on the kura lane
                // `tuist generate` writes it into the project pointing at the proxy, and
                // the plugin consumes that option rather than forwarding it to Xcode's own
                // remote client.
                let baseArguments = [
                    "-scheme", "App",
                    "-destination", "generic/platform=iOS Simulator",
                    "-project", xcodeprojPath.pathString,
                    "CODE_SIGN_IDENTITY=",
                    "CODE_SIGNING_REQUIRED=NO",
                    "CODE_SIGNING_ALLOWED=NO",
                ]
                // Every build writes to this same derived data path: the absolute path of a
                // compilation's outputs is part of its cache key, so a rebuild that writes
                // elsewhere cannot hit what this one publishes.
                let derivedDataPath = temporaryDirectory.appending(component: "derived-data")
                let buildArguments = baseArguments + ["-derivedDataPath", derivedDataPath.pathString]
                try await TuistTest.run(
                    XcodeBuildBuildCommand.self,
                    buildArguments + casArguments(in: temporaryDirectory, name: "cold")
                )
                TuistTest.expectLogs("cacheable tasks (0%)")
                resetUI()

                try await expectFullyCachedRebuild(
                    arguments: buildArguments,
                    derivedDataPath: derivedDataPath,
                    casParentDirectory: temporaryDirectory,
                    fileSystem: fileSystem
                )
            }
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_multiplatform_app", accountHandle: "tuist")
    ) func multiplatform_app_module_cache() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // When: Generate with focus on App
        try await TuistTest.run(
            GenerateCommand.self, ["App", "--path", fixtureDirectory.pathString, "--no-open"]
        )

        // Then: Cached frameworks should be linked as xcframeworks
        try TuistAcceptanceTest.expectXCFrameworkLinked(
            "MacOSStaticFramework", by: "App", xcodeprojPath: xcodeprojPath
        )
        try TuistAcceptanceTest.expectXCFrameworkLinked(
            "MultiPlatformTransitiveDynamicFramework", by: "App", xcodeprojPath: xcodeprojPath
        )

        // When: Build the project for macOS
        let arguments = [
            "-scheme", "App",
            "-destination", "platform=macOS",
            "-project", xcodeprojPath.pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
            "CODE_SIGN_IDENTITY=",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGNING_ALLOWED=NO",
        ]
        try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_multiplatform_app", accountHandle: "tuist")
    ) func multiplatform_app_selective_testing() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        // When: Run tests for the first time
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path", fixtureDirectory.pathString,
                "--derived-data-path", temporaryDirectory.pathString,
                "--platform", "macOS",
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        let unchangedTestTargetName = "MultiPlatformTransitiveDynamicFrameworkTests"
        let unchangedTestHash = try await selectiveTestingHash(
            for: unchangedTestTargetName,
            fixtureDirectory: fixtureDirectory
        )
        try await waitForRemoteSelectiveTestResult(
            targetName: unchangedTestTargetName,
            hash: unchangedTestHash,
            fixtureDirectory: fixtureDirectory,
            fileSystem: fileSystem
        )

        // When: Clean selective testing data
        try await TuistTest.run(
            CleanCommand.self, ["selectiveTests", "--path", fixtureDirectory.pathString]
        )
        resetUI()

        // When: Modify MacOSStaticFramework source
        let filePath = fixtureDirectory.appending(
            try RelativePath(validating: "Modules/MacOSStaticFramework/Sources/MacOSStaticFrameworkClass.swift")
        )
        try await fileSystem.writeText(
            """
            \(try await fileSystem.readTextFile(at: filePath))
            // \(UUID().uuidString)
            """, at: filePath, options: Set([.overwrite])
        )

        // When: Run tests again
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path", fixtureDirectory.pathString,
                "--derived-data-path", temporaryDirectory.pathString,
                "--platform", "macOS",
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        // Then: Expect MultiPlatformTransitiveDynamicFrameworkTests to be skipped (unchanged)
        TuistTest.expectLogs(
            "The following targets have not changed since the last successful run and will be skipped: MultiPlatformTransitiveDynamicFrameworkTests"
        )
    }

    /// The remote compilation cache is eventually consistent: the outputs uploaded at the very end of
    /// the first build (the `App` target's own objects, stored last) can lag behind on an immediate warm
    /// rebuild, so a single clean rebuild does not reliably reach a 100% hit rate. Retry the clean rebuild
    /// until every cacheable task is served from the cache, mirroring how `waitForRemoteSelectiveTestResult`
    /// polls the same backend instead of asserting on the first attempt.
    private func expectFullyCachedRebuild(
        arguments: [String],
        derivedDataPath: AbsolutePath,
        casParentDirectory: AbsolutePath,
        fileSystem: FileSysteming,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(180))
        var attempt = 0

        while true {
            attempt += 1
            // Removing derived data is what forces the rebuild, and recreating it at the
            // same path is what keeps the outputs, and with them the cache keys, equal to
            // the ones the cold build published. The local CAS is elsewhere, so this
            // neither warms the rebuild nor races the proxy's spool.
            try await fileSystem.remove(derivedDataPath)
            try await TuistTest.run(
                XcodeBuildBuildCommand.self,
                arguments + casArguments(in: casParentDirectory, name: "warm-\(attempt)")
            )

            if Logger.testingLogHandler.collected[.warning, >=].contains("cacheable tasks (100%)") {
                return
            }

            if clock.now >= deadline {
                TuistTest.expectLogs("cacheable tasks (100%)", sourceLocation: sourceLocation)
                return
            }

            resetUI()
        }
    }

    /// Puts the local CAS in a caller-owned directory outside derived data.
    ///
    /// The CAS path is not part of a compilation's cache key, so a fresh directory per build
    /// leaves the keys untouched while emptying the local store: what a build hits then came
    /// from the remote. Keeping it out of derived data also keeps the proxy's write-ahead
    /// spool, which lives at `<cas path>/tuist-spool`, clear of what the rebuild loop removes.
    private func casArguments(in parentDirectory: AbsolutePath, name: String) -> [String] {
        let casPath = parentDirectory.appending(component: "cas-\(name)")
        return ["COMPILATION_CACHE_CAS_PATH=\(casPath.pathString)"]
    }

    private func selectiveTestingHash(
        for targetName: String,
        fixtureDirectory: AbsolutePath
    ) async throws -> String {
        try await TuistTest.run(HashSelectiveTestingCommand.self, ["--path", fixtureDirectory.pathString])

        let prefix = "\(targetName) - "
        let output = Logger.testingLogHandler.collected[.info, <=]
        let line = try #require(
            output
                .split(separator: "\n")
                .reversed()
                .first(where: { $0.hasPrefix(prefix) }),
            "Selective testing hash for \(targetName) was not found in logs: \(output)"
        )
        return String(line.dropFirst(prefix.count))
    }

    /// Remote selective-test results become visible asynchronously on canary. Poll the same cache
    /// lookup the second `tuist test` run depends on instead of sleeping for a fixed duration.
    private func waitForRemoteSelectiveTestResult(
        targetName: String,
        hash: String,
        fixtureDirectory: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws {
        let config = try await ConfigLoader().loadConfig(path: fixtureDirectory)
        let cacheStorage = try await CacheStorageFactory().cacheStorage(config: config)
        let expectedItem = CacheStorableItem(name: targetName, hash: hash)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(60))

        while true {
            try await cleanLocalSelectiveTestsCache(fileSystem: fileSystem)
            let fetchedItems = try await cacheStorage.fetch(Set([expectedItem]), cacheCategory: .selectiveTests)
            if fetchedItems.keys.contains(where: { $0.hash == hash }) {
                return
            }

            try #require(
                clock.now < deadline,
                "Remote selective test result for \(targetName) with hash \(hash) did not become available"
            )
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func cleanLocalSelectiveTestsCache(fileSystem: FileSysteming) async throws {
        let directory = try CacheDirectoriesProvider().cacheDirectory(for: .selectiveTests)
        if try await fileSystem.exists(directory) {
            try await fileSystem.remove(directory)
        }
        try await fileSystem.makeDirectory(at: directory)
    }

    /// Where `mise run build` in `cas-plugin` leaves the plugin dylib and the proxy binary.
    ///
    /// Resolved from the source tree, the way `Fixtures.directory` is, rather than from
    /// `TUIST_CAS_PLUGIN_PATH`: `xcodebuild test-without-building` runs the bundle with the
    /// environment captured into the xctestrun at build time, so a variable exported by the
    /// CI job never reaches this process.
    private func casPluginBuildDirectory() throws -> AbsolutePath {
        try AbsolutePath(validating: #filePath)
            .parentDirectory
            .parentDirectory
            .parentDirectory
            .parentDirectory
            .appending(components: "cas-plugin", "target", "release")
    }

    /// The cache proxy exposes a Unix-domain socket under the state directory. macOS limits the full
    /// socket path length, so acceptance tests use a short state directory to keep the socket path valid.
    private func makeShortStateDirectory(fileSystem: FileSysteming) async throws -> AbsolutePath {
        let directory = try AbsolutePath(validating: "/tmp")
            .appending(component: "tuist-cache-\(UUID().uuidString.prefix(8).lowercased())")
        try await fileSystem.makeDirectory(at: directory)
        return directory
    }

    private func withShortStateDirectory(
        fileSystem: FileSysteming,
        operation: (AbsolutePath) async throws -> Void
    ) async throws {
        let directory = try await makeShortStateDirectory(fileSystem: fileSystem)

        do {
            try await operation(directory)
        } catch {
            try? await fileSystem.remove(directory)
            throw error
        }

        try? await fileSystem.remove(directory)
    }

    /// Runs the per-machine CAS proxy for the duration of `operation`.
    ///
    /// `cache-proxy` cannot serve here: it hands off with `execv`, which would replace
    /// the test runner's process image. The proxy binary is spawned directly instead,
    /// configured the way `CacheProxyCommandService` configures it, except that the
    /// bearer is passed as `TUIST_CAS_TOKEN` because the proxy's other option is to
    /// shell out to a `tuist` binary this process does not have.
    ///
    /// That bearer is the cache-scoped token from `CacheTokenStore`, not the session
    /// token `tuist auth token` prints: kura rejects the latter with "Invalid or
    /// expired token" and serves nothing.
    private func withCacheProxy(
        executablePath: AbsolutePath,
        fullHandle: String,
        socketPath: AbsolutePath,
        fileSystem: FileSysteming,
        operation: () async throws -> Void
    ) async throws {
        let serverURL = try #require(
            URL(string: Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")
        )
        let accountHandle = String(fullHandle.split(separator: "/")[0])
        let endpoint = try await CacheURLStore().getCacheURL(for: serverURL, accountHandle: accountHandle)
        let token = try #require(
            await CacheTokenStore.shared.cacheToken(authenticationURL: serverURL, fullHandle: fullHandle),
            "The acceptance test could not mint a cache token for \(fullHandle) against \(serverURL.absoluteString)"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath.pathString)
        process.environment = [
            "TUIST_CAS_PROXY_SOCKET": socketPath.pathString,
            "TUIST_CAS_REMOTE_GRPC_URL": endpoint.absoluteString,
            "TUIST_CAS_SERVER_URL": serverURL.absoluteString,
            "TUIST_CAS_TOKEN": token,
            // The proxy and the build start together, so there is no window to warm a
            // byte closure in. This is what `tuist setup cache` selects on CI.
            "TUIST_CAS_PREFETCH": "keys",
            // The proxy resolves the wrapped Apple plugin through `xcode-select`.
            "PATH": Environment.current.variables["PATH"] ?? "",
        ]
        try process.run()

        do {
            try await waitForSocket(at: socketPath, fileSystem: fileSystem, process: process)
            try await operation()
        } catch {
            stopCacheProxy(process)
            throw error
        }

        stopCacheProxy(process)
    }

    private func stopCacheProxy(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    private func waitForSocket(
        at socketPath: AbsolutePath,
        fileSystem: FileSysteming,
        process: Process
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))

        while try await !fileSystem.exists(socketPath) {
            // The proxy exits non-zero on a missing endpoint or a socket it cannot bind,
            // and waiting out the deadline would report that as a timeout.
            try #require(
                process.isRunning,
                "The cache proxy exited with status \(process.terminationStatus) before binding \(socketPath.pathString)"
            )
            try #require(
                clock.now < deadline,
                "Cache proxy did not create socket at \(socketPath.pathString)"
            )
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
