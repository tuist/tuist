import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistCacheCommand
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
        environment.stateDirectory = try await fileSystem.currentWorkingDirectory()
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

        let backgroundTask = Task {
            while !Task.isCancelled {
                try await TuistTest.run(
                    CacheStartCommand.self,
                    [fixtureFullHandle, "--url", Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev"]
                )
            }
        }

        defer {
            backgroundTask.cancel()
        }

        let remoteCacheServicePath = environment.stateDirectory
            .appending(component: "\(fixtureFullHandle.replacingOccurrences(of: "/", with: "_")).sock")

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

    // FIXME(#10528): Fails consistently on CI against canary; quarantined until diagnosed.
    @Test(
        .disabled("Quarantined: see https://github.com/tuist/tuist/issues/10528"),
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

    // FIXME(#10528): Fails consistently on CI against canary; quarantined until diagnosed.
    @Test(
        .disabled("Quarantined: see https://github.com/tuist/tuist/issues/10528"),
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

        // Selective test results are persisted asynchronously
        try await Task.sleep(nanoseconds: 7_000_000_000)

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
}
