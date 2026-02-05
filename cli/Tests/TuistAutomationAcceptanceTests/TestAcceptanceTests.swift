import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct TestAcceptanceTests {
    @Test(
        .withFixture("generated_ios_app_with_frameworks"),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func ios_app_with_frameworks() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When/Then
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )
    }

    @Test(
        .withFixture("generated_app_with_framework_and_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func app_with_framework_and_tests() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When/Then
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

    @Test(
        .withFixture("generated_ios_app_with_static_framework_resource_tests_and_metal"),
        .inTemporaryDirectory,
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func ios_app_with_static_framework_resources_and_metal() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        // When/Then: test execution should succeed
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString, "App"]
        )

        let productsPath = temporaryDirectory.appending(components: "Build", "Products")
        let matches = try await fileSystem.glob(
            directory: productsPath,
            include: ["**/App.app"]
        ).collect()
        let appPath = try #require(matches.first)
        let metallibPath = appPath.appending(
            components: "Frameworks",
            "StaticMetalFramework.framework",
            "default.metallib"
        )
        #expect(try await fileSystem.exists(metallibPath))
    }
}

/// Test projects using tuist test
struct TestAcceptanceTestCases {
    @Test(.withFixture("generated_framework_with_spm_bundle"), .inTemporaryDirectory)
    func with_framework_with_spm_bundle() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }

    @Test(.withFixture("generated_app_with_test_plan"), .inTemporaryDirectory)
    func with_app_with_test_plan() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
        try await TuistTest.run(
            TestCommand.self,
            ["App", "--test-plan", "All", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }

    @Test(.withFixture("generated_app_workspace_with_test_plan"), .inTemporaryDirectory)
    func with_app_workspace_with_test_plan() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let derivedDataPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.run(
            TestCommand.self,
            ["App", "--test-plan", "AppTestPlan", "--path", fixtureDirectory.pathString, "--derived-data-path", derivedDataPath.pathString]
        )
    }

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
    }

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
