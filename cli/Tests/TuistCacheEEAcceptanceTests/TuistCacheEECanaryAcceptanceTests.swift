import FileSystem
import FileSystemTesting
import Foundation
import Logging
import Path
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistCacheCommand
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
        .withFixtureConnectedToCanary("generated_project_with_caching_enabled")
    ) func generated_project_with_caching_enabled() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "App.xcodeproj")
        let fileSystem = FileSystem()
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)

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

            let remoteCacheServicePath = environment.stateDirectory
                .appending(component: "\(fixtureFullHandle.replacingOccurrences(of: "/", with: "_")).sock")
            try #require(
                remoteCacheServicePath.pathString.utf8.count < 104,
                "Unix-domain socket path is too long: \(remoteCacheServicePath.pathString)"
            )

            try await withCacheServer(
                fullHandle: fixtureFullHandle,
                socketPath: remoteCacheServicePath,
                fileSystem: fileSystem
            ) {
                try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
                resetUI()

                let arguments = [
                    "-scheme", "App",
                    "-destination", "generic/platform=iOS Simulator",
                    "-project", xcodeprojPath.pathString,
                    "-derivedDataPath", temporaryDirectory.pathString,
                    "CODE_SIGN_IDENTITY=",
                    "CODE_SIGNING_REQUIRED=NO",
                    "CODE_SIGNING_ALLOWED=NO",
                    "COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(remoteCacheServicePath.pathString)",
                ]
                try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
                TuistTest.expectLogs("cacheable tasks (0%)")
                resetUI()

                try await fileSystem.remove(temporaryDirectory)

                try await TuistTest.run(XcodeBuildBuildCommand.self, arguments)
                TuistTest.expectLogs("cacheable tasks (100%)")
            }
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_multiplatform_app")
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
        .withFixtureConnectedToCanary("generated_multiplatform_app")
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

    /// The cache server exposes a Unix-domain socket under the state directory. macOS limits the full
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

    private func withCacheServer(
        fullHandle: String,
        socketPath: AbsolutePath,
        fileSystem: FileSysteming,
        operation: () async throws -> Void
    ) async throws {
        let cacheServerTask = Task {
            try await TuistTest.run(
                CacheStartCommand.self,
                [fullHandle, "--url", Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev"]
            )
        }

        do {
            try await waitForCacheServer(at: socketPath, fileSystem: fileSystem)
            try await operation()
        } catch {
            await stopCacheServer(cacheServerTask)
            throw error
        }

        await stopCacheServer(cacheServerTask)
    }

    private func stopCacheServer(_ task: Task<Void, Error>) async {
        task.cancel()
        _ = await task.result
    }

    private func waitForCacheServer(
        at socketPath: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))

        while try await !fileSystem.exists(socketPath) {
            try #require(
                clock.now < deadline,
                "Cache server did not create socket at \(socketPath.pathString)"
            )
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
