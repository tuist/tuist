import Command
import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistAcceptanceTesting
import TuistCore
import TuistSupport
import TuistTesting
import XCTest

@testable import TuistKit

struct InspectAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    )
    func build() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let arguments = [
            "-scheme", "App",
            "-destination", "generic/platform=iOS Simulator",
            "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
            "-resultBundlePath", fixtureDirectory.appending(component: "result.xcresult").pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
        ]

        // When: I build the app
        try await TuistTest.run(
            XcodeBuildBuildCommand.self,
            arguments
        )

        // When: I inspect the bundle
        try await TuistTest.run(
            InspectBuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )

        // Then
        #expect(ui().contains("View the analyzed build at"))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    )
    func test() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        // When: I build the app
        let commandRunner = CommandRunner()
        try await commandRunner.run(
            arguments: [
                "/usr/bin/xcrun",
                "xcodebuild",
                "clean",
                "test",
                "-scheme", "App",
                "-destination", "platform=iOS Simulator,name=iPhone 17",
                "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
                "-derivedDataPath", temporaryDirectory.pathString,
            ]
        ).pipedStream().awaitCompletion()

        // When: I inspect the test
        try await TuistTest.run(
            InspectTestCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )

        // Then
        #expect(ui().contains("View the analyzed test at"))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("xcode_project_with_inspect_build")
    )
    func bundle() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let arguments = [
            "-scheme", "App",
            "-destination", "generic/platform=iOS Simulator",
            "-project", fixtureDirectory.appending(component: "App.xcodeproj").pathString,
            "-resultBundlePath", fixtureDirectory.appending(component: "result.xcresult").pathString,
            "-derivedDataPath", temporaryDirectory.pathString,
        ]

        // When: I build the app
        try await TuistTest.run(
            XcodeBuildBuildCommand.self,
            arguments
        )

        // When: I inspect the bundle
        try await TuistTest.run(
            InspectBundleCommand.self,
            [
                "--path",
                fixtureDirectory.pathString,
                temporaryDirectory.appending(components: "Build", "Products", "Debug-iphonesimulator", "App.app").pathString,
            ]
        )

        // Then
        #expect(ui().contains("""
        ✔︎ Bundle analyzed
        """) == true)
    }
}

final class LintAcceptanceTests: TuistAcceptanceTestCase {
    func test_ios_app_with_headers() async throws {
        try await withMockedDependencies {
            try await setUpFixture("generated_ios_app_with_headers")
            try await run(InspectImplicitImportsCommand.self)
            XCTAssertStandardOutput(pattern: "We did not find any implicit dependencies in your project.")
        }
    }

    func test_ios_app_with_implicit_dependencies() async throws {
        try await withMockedDependencies {
            try await setUpFixture("generated_ios_app_with_implicit_dependencies")
            let appDependencies: Set<String> = [
                "ClassModule",
                "EnumModule",
                "FuncModule",
                "LetModule",
                "ProtocolModule",
                "StructModule",
                "TypeAliasModule",
                "VarModule",
            ]
            let expectedAppIssue = InspectImportsIssue(target: "App", dependencies: appDependencies)
            let expectedFrameworkIssue = InspectImportsIssue(target: "FrameworkA", dependencies: ["FrameworkB"])
            let expectedError = InspectImportsServiceError.implicitImportsFound([expectedAppIssue, expectedFrameworkIssue])

            await XCTAssertThrowsSpecific(try await run(InspectImplicitImportsCommand.self), expectedError)
        }
    }

    func test_framework_with_macros_redundant_imports() async throws {
        try await withMockedDependencies {
            try await setUpFixture("generated_framework_with_macros_and_tests")
            try await run(InstallCommand.self)
            try await run(InspectRedundantImportsCommand.self)
            XCTAssertStandardOutput(pattern: "We did not find any redundant dependencies in your project.")
        }
    }
}
