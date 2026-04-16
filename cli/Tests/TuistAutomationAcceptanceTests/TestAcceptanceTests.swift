import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistAcceptanceTesting
import TuistBuildCommand
import TuistEnvironment
import TuistSupport
import TuistTestCommand
import TuistTesting

@testable import TuistKit

struct TestAcceptanceTestiOSAppWithFrameworks {
    @Test(
        .disabled(),
        .withFixture("generated_ios_app_with_frameworks"),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func ios_app_with_frameworks() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
    }
}

struct TestAcceptanceTestAppWithFrameworkAndTests {
    @Test(
        .disabled(),
        .withFixture("generated_app_with_framework_and_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func app_with_framework_and_tests() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString, "App"]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "--test-targets",
                "FrameworkTests/FrameworkTests",
            ]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                temporaryDirectory.pathString,
                "App",
                "--",
                "-testLanguage",
                "en",
            ]
        )
    }
}

struct TestAcceptanceTestFrameworkWithSPMBundle {
    @Test(.disabled(), .withFixture("generated_framework_with_spm_bundle"), .inTemporaryDirectory)
    func with_framework_with_spm_bundle() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct TestAcceptanceTestAppWithTestPlan {
    @Test(.disabled(), .withFixture("generated_app_with_test_plan"), .inTemporaryDirectory)
    func with_app_with_test_plan() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            TestCommand.self,
            [
                "App",
                "--test-plan",
                "All",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
    }
}

struct TestAcceptanceTestAppWorkspaceWithTestPlan {
    @Test(.disabled(), .withFixture("generated_app_workspace_with_test_plan"), .inTemporaryDirectory)
    func with_app_workspace_with_test_plan() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            [
                "App",
                "--test-plan",
                "AppTestPlan",
                "--path",
                fixtureDirectory.pathString,
                "--derived-data-path",
                derivedDataPath.pathString,
            ]
        )
    }
}

struct TestAcceptanceTestInvalidArguments {
    @Test(.withFixture("generated_app_with_framework_and_tests"), .inTemporaryDirectory)
    func with_invalid_arguments() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-scheme")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-scheme",
                    "App",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-project")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-project",
                    "App",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-workspace")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-workspace",
                    "App",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-testPlan")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-testPlan",
                    "TestPlan",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-test-configuration")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-skip-test-configuration",
                    "TestPlan",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-only-test-configuration")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-only-test-configuration",
                    "TestPlan",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-only-testing")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-only-testing",
                    "AppTests",
                ]
            )
        }
        await #expect(throws: XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-testing")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-skip-testing",
                    "AppTests",
                ]
            )
        }
        await #expect(throws: Error.self) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-parallelizeTargets",
                    "YES",
                    "-enableAddressSanitizer",
                ]
            )
        }
        await #expect(throws: Error.self) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--configuration",
                    "Debug",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "-configuration",
                    "Debug",
                ]
            )
        }
        await #expect(throws: TuistTestFlagError.passthroughActionVerbConflict("build-for-testing")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--build-only",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "build-for-testing",
                    "-configuration",
                    "Debug",
                ]
            )
        }
        await #expect(throws: TuistTestFlagError.passthroughActionVerbConflict("test")) {
            try await TuistTest.run(
                TestCommand.self,
                [
                    "App",
                    "--path",
                    fixtureDirectory.pathString,
                    "--derived-data-path",
                    derivedDataPath.pathString,
                    "--",
                    "test",
                ]
            )
        }
    }
}

struct TestAcceptanceTestMultiplatformApp {
    @Test(.withFixture("generated_multiplatform_app"), .inTemporaryDirectory)
    func with_multiplatform_app() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }
}

struct TestAcceptanceTestShardWithRemoteTestProducts {
    @Test(
        .withFixtureConnectedToCanary("generated_ios_app_with_tests"),
        .inTemporaryDirectory
    ) func shard_with_remote_test_products() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "MacFrameworkTests.xctestproducts")
        let shardReference = "acceptance-test-\(Int.random(in: 100_000 ... 999_999))"

        Environment.mocked?.variables["GITHUB_ACTIONS"] = "true"
        Environment.mocked?.variables["GITHUB_RUN_ID"] = shardReference
        Environment.mocked?.variables["GITHUB_RUN_ATTEMPT"] = "1"
        let githubOutputPath = temporaryDirectory.appending(component: "github_output")
        try await FileSystem().writeText("", at: githubOutputPath)
        Environment.mocked?.variables["GITHUB_OUTPUT"] = githubOutputPath.pathString

        // Build phase: build tests and upload shard archive to server
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--build-only",
                "--shard-total", "1",
                "--path", fixtureDirectory.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )

        // Test phase: download shard archive and run tests
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--without-building",
                "--shard-index", "0",
                "--path", fixtureDirectory.pathString,
                "--",
                "-destination", "platform=macOS",
            ]
        )
    }
}

struct TestAcceptanceTestShardWithLocalTestProducts {
    @Test(
        .withFixtureConnectedToCanary("generated_ios_app_with_tests"),
        .inTemporaryDirectory
    ) func shard_with_local_test_products() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "MacFrameworkTests.xctestproducts")
        let shardReference = "acceptance-test-\(Int.random(in: 100_000 ... 999_999))"

        // Set CI env vars so ShardService can derive the shard reference
        Environment.mocked?.variables["GITHUB_ACTIONS"] = "true"
        Environment.mocked?.variables["GITHUB_RUN_ID"] = shardReference
        Environment.mocked?.variables["GITHUB_RUN_ATTEMPT"] = "1"
        let githubOutputPath = temporaryDirectory.appending(component: "github_output")
        try await FileSystem().writeText("", at: githubOutputPath)
        Environment.mocked?.variables["GITHUB_OUTPUT"] = githubOutputPath.pathString

        // Build phase: build tests and create shard plan, skip S3 upload
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--build-only",
                "--shard-total", "1",
                "--shard-skip-upload",
                "--path", fixtureDirectory.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )

        // Test phase: run shard using local test products
        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--without-building",
                "--shard-index", "0",
                "--path", fixtureDirectory.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )
    }
}
