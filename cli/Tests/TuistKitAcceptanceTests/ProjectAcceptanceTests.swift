import Foundation
import Testing
import TuistAcceptanceTesting
import TuistLoggerTesting
import TuistLogging
import TuistNooraTesting
import TuistSupport
import TuistTesting

@testable import TuistKit

struct ProjectAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    )
    func bundle() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)

        // When: Lists the projects
        try await TuistTest.run(
            ProjectListCommand.self,
            ["--path", fixtureDirectory.pathString]
        )

        // Then: It contains the project that I expect
        TuistTest.expectLogs("Listing all your projects:")
        TuistTest.expectLogs("• \(fullHandle)")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    )
    func revoke_project_token() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)

        // When
        try await TuistTest.run(
            ProjectTokensCreateCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        try await TuistTest.run(
            ProjectTokensListCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        let uiOutput = ui()
        let id = try #require(
            uiOutput.components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard let uuid = try? /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/
                        .firstMatch(in: trimmed)
                    else { return nil }
                    return String(uuid.output)
                }
                .first
        )
        resetUI()
        try await TuistTest.run(
            ProjectTokensRevokeCommand.self,
            ["--path", fixtureDirectory.pathString, id, fullHandle]
        )
        try await TuistTest.run(
            ProjectTokensListCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )

        // Then
        TuistTest.expectLogs("No project tokens found. Create one by running `tuist project tokens create \(fullHandle).")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    )
    func update_default_branch() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)

        // When
        try await TuistTest.run(
            ProjectShowCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        TuistTest.expectLogs("""
        Full handle: \(fullHandle)
        Default branch: main
        """)
        try await TuistTest.run(
            ProjectUpdateCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle, "--default-branch", "new-default-branch"]
        )
        try await TuistTest.run(
            ProjectShowCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        TuistTest.expectLogs("""
        Full handle: \(fullHandle)
        Default branch: new-default-branch
        """)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    )
    func update_the_project_visibility() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)

        // When
        try await TuistTest.run(
            ProjectShowCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        TuistTest.expectLogs("""
        Visibility: private
        """)
        try await TuistTest.run(
            ProjectUpdateCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle, "--visibility", "public"]
        )
        try await TuistTest.run(
            ProjectShowCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        TuistTest.expectLogs("""
        Visibility: public
        """)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    )
    func update_the_project_repository() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fullHandle = try #require(TuistTest.fixtureFullHandle)

        // When
        try await TuistTest.run(
            ProjectShowCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        TuistTest.expectLogs("""
        Full handle: \(fullHandle)
        Default branch: main
        """)
        try await TuistTest.run(
            ProjectShowCommand.self,
            ["--path", fixtureDirectory.pathString, fullHandle]
        )
        TuistTest.expectLogs("""
        Full handle: \(fullHandle)
        Default branch: main
        """)
    }
}
