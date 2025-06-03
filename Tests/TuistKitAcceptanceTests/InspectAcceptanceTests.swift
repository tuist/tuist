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
            ["--path", fixtureDirectory.pathString, "--project-derived-data-path", temporaryDirectory.pathString]
        )

        // Then
        #expect(ui().contains("""
        ✔ Success
          Uploaded a build to the server.
        """) == true)
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
            try await setUpFixture(.iosAppWithHeaders)
            try await run(InspectImplicitImportsCommand.self)
            XCTAssertStandardOutput(pattern: "We did not find any implicit dependencies in your project.")
        }
    }

    func test_ios_app_with_implicit_dependencies() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.iosAppWithImplicitDependencies)
            await XCTAssertThrowsSpecific(try await run(InspectImplicitImportsCommand.self), LintingError())
            XCTAssertStandardOutput(pattern: """
             - FrameworkA implicitly depends on: FrameworkB
            """)
        }
    }
}
