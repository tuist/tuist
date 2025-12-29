import FileSystem
import FileSystemTesting
import Testing
import TuistAcceptanceTesting
import TuistSupport
import TuistTesting
import XCTest

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
}

/// Test projects using tuist test
final class TestXCTestAcceptanceTests: TuistAcceptanceTestCase {
    func test_with_framework_with_spm_bundle() async throws {
        try await setUpFixture("generated_framework_with_spm_bundle")
        try await run(InstallCommand.self)
        try await run(TestCommand.self)
    }

    func test_with_app_with_test_plan() async throws {
        try await setUpFixture("generated_app_with_test_plan")
        try await run(TestCommand.self)
        try await run(TestCommand.self, "App", "--test-plan", "All")
    }

    func test_with_app_workspace_with_test_plan() async throws {
        try await setUpFixture("generated_app_workspace_with_test_plan")
        try await run(TestCommand.self, "App", "--test-plan", "AppTestPlan")
    }

    func test_with_invalid_arguments() async throws {
        try await setUpFixture("generated_app_with_framework_and_tests")
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-scheme", "App"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-scheme")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-project", "App"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-project")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-workspace", "App"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-workspace")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-testPlan", "TestPlan"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-testPlan")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-skip-test-configuration", "TestPlan"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-test-configuration")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-only-test-configuration", "TestPlan"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-only-test-configuration")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-only-testing", "AppTests"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-only-testing")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-skip-testing", "AppTests"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-testing")
        )
        // SystemError is verbose and would lead to flakyness
        // xcodebuild: error: The flag -addressSanitizerEnabled must be supplied with an argument YES or NO
        await XCTAssertThrows(
            try await run(TestCommand.self, "App", "--", "-parallelizeTargets", "YES", "-enableAddressSanitizer")
        )
        // xcodebuild: error: option '-configuration' may only be provided once
        // Usage: xcodebuild [-project <projectname>] ...
        await XCTAssertThrows(
            try await run(TestCommand.self, "App", "--configuration", "Debug", "--", "-configuration", "Debug")
        )
    }

    func test_with_multiplatform_app() async throws {
        try await setUpFixture("generated_multiplatform_app")
        try await run(TestCommand.self)
    }
}
