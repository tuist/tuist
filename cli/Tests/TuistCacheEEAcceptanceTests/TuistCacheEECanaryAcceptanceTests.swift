import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistServer
import TuistSupport
import TuistTesting
import XcodeProj

@testable import TuistCacheEE

struct TuistCacheEECanaryAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withTestingSimulator("iPhone 17"),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    ) func ios_app_with_frameworks() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "MainApp.xcodeproj")
        let fileSystem = FileSystem()
        let simulator = try #require(Simulator.testing)

        // When: Cache
        try await TuistTest.run(CacheCommand.self, ["--path", fixtureDirectory.pathString])

        // When: Test
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path", fixtureDirectory.pathString, "--derived-data-path",
                temporaryDirectory.pathString, "--device", simulator.name,
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        // Selective test results are persisted asynchronously and can take up to 5
        // seconds to be inserted.
        try await Task.sleep(nanoseconds: 7_000_000_000)

        // When: Clean selective testing data and local binaries
        try await TuistTest.run(
            CleanCommand.self, ["binaries", "--path", fixtureDirectory.pathString]
        )
        try await TuistTest.run(
            CleanCommand.self, ["selectiveTests", "--path", fixtureDirectory.pathString]
        )
        resetUI()

        // When: I change a file and cache again
        let filePath = fixtureDirectory.appending(
            try RelativePath(validating: "Framework1/Sources/Framework1File.swift")
        )
        try await fileSystem.writeText(
            """
            \(try await fileSystem.readTextFile(at: filePath))
            // \(UUID().uuidString)
            """, at: filePath, options: Set([.overwrite])
        )
        try await TuistTest.run(CacheCommand.self, ["--path", fixtureDirectory.pathString])

        // Then: I expect one framework to be stored
        TuistTest.expectLogs("1 target stored: Framework1")

        // When: I generate and build the project for App
        try await TuistTest.run(
            GenerateCommand.self, ["App", "--path", fixtureDirectory.pathString, "--no-open"]
        )
        try await TuistTest.run(
            BuildCommand.self,
            [
                "App",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "--",
                "-resultBundlePath",
                temporaryDirectory.appending(component: "\(UUID().uuidString).xcresult").pathString,
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        // Then: I expect Framework1 to come from the cache
        try TuistAcceptanceTest.expectXCFrameworkLinked(
            "Framework1", by: "App", xcodeprojPath: xcodeprojPath
        )
        resetUI()

        // When: I run the tests
        resetUI()
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path", fixtureDirectory.pathString, "--derived-data-path",
                temporaryDirectory.pathString, "--device", simulator.name,
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        // Then: Expect to skip the tests for Framework2Tests
        TuistTest
            .expectLogs(
                "The following targets have not changed since the last successful run and will be skipped: Framework2Tests"
            )

        // When: I run the tests for Framework1
        resetUI()
        try await TuistTest.run(
            TestCommand.self,
            [
                "Framework1", "--path", fixtureDirectory.pathString, "--derived-data-path",
                temporaryDirectory.pathString, "--device", simulator.name,
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        // Then: I expect to skip tests for Framework1
        TuistTest.expectLogs(
            "The scheme Framework1's test action has no tests to run, finishing early."
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withTestingSimulator("iPhone 17"),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    ) func run_with_no_selective_testing() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let simulator = try #require(Simulator.testing)

        // When: I run tests for the first time
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "--device",
                simulator.name,
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )
        resetUI()

        // When: I run them again without selective testing
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "--device",
                simulator.name,
                "--",
                "CODE_SIGN_IDENTITY=",
                "CODE_SIGNING_REQUIRED=NO",
                "CODE_SIGNING_ALLOWED=NO",
            ]
        )

        // Then: Results should be stored
        TuistTest.expectLogs("Storing remote selectiveTests. Hold tight...")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    ) func ios_app_with_frameworks_when_no_remote_artifacts() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fileSystem = FileSystem()

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // Selective test results are persisted asynchronously and can take up to 5
        // seconds to be inserted.
        try await Task.sleep(nanoseconds: 7_000_000_000)

        // When: Clean binaries
        try await TuistTest.run(
            CleanCommand.self, ["binaries", "--path", fixtureDirectory.pathString]
        )

        // When: I change some local files
        try await fileSystem.writeText(
            "// \(UUID().uuidString)",
            at: try fixtureDirectory.appending(
                RelativePath(validating: "Framework1/Sources/Framework1File.swift")
            ),
            options: Set([.overwrite])
        )
        try await fileSystem.writeText(
            "// \(UUID().uuidString)",
            at: try fixtureDirectory.appending(
                RelativePath(validating: "Framework2/Sources/Framework2File.swift")
            ),
            options: Set([.overwrite])
        )
        try await fileSystem.writeText(
            "// \(UUID().uuidString)",
            at: try fixtureDirectory.appending(
                RelativePath(validating: "Framework3/Sources/Framework3File.swift")
            ),
            options: Set([.overwrite])
        )
        try await fileSystem.writeText(
            "// \(UUID().uuidString)",
            at: try fixtureDirectory.appending(
                RelativePath(validating: "Framework4/Sources/Framework4File.swift")
            ),
            options: Set([.overwrite])
        )
        try await fileSystem.writeText(
            "// \(UUID().uuidString)",
            at: try fixtureDirectory.appending(
                RelativePath(validating: "Framework5/Sources/Framework5File.swift")
            ),
            options: Set([.overwrite])
        )

        // Then: The project generates
        try await TuistTest.run(
            GenerateCommand.self, ["App", "--path", fixtureDirectory.pathString, "--no-open"]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    ) func clean_remote_cache() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let xcodeprojPath = fixtureDirectory.appending(component: "MainApp.xcodeproj")

        // When: Cache the binaries
        try await TuistTest.run(
            CacheCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // Then: Framework1 is linked as binary
        try await TuistTest.run(
            GenerateCommand.self, ["App", "--path", fixtureDirectory.pathString, "--no-open"]
        )
        try TuistAcceptanceTest.expectXCFrameworkLinked(
            "Framework1", by: "App", xcodeprojPath: xcodeprojPath
        )

        // When: Clean binaries
        try await TuistTest.run(
            CleanCommand.self, ["binaries", "--path", fixtureDirectory.pathString, "--remote"]
        )

        // Clean is performed asynchronously, so we need to wait for the clean to be finished.
        try await Task.sleep(nanoseconds: 7_000_000_000)

        // Then: Framework1 is not linked as a binary
        try await TuistTest.run(
            GenerateCommand.self, ["App", "--path", fixtureDirectory.pathString, "--no-open"]
        )
        try TuistAcceptanceTest.expectXCFrameworkNotLinked(
            "Framework1", by: "App", xcodeprojPath: xcodeprojPath
        )
    }
}
