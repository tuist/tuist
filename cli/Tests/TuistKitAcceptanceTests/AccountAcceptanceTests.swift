import Foundation
import Testing
import TuistAcceptanceTesting
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct AccountAcceptanceTests {
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    )
    func account_with_logged_in_user() async throws {
        // By default, the CLI refreshes in the background spawning itself in a subprocess.
        // This is something we can't do from accepance tests, so we configure that behaviour
        // using the task local.
        try await ServerAuthenticationConfig.$current.withValue(ServerAuthenticationConfig(backgroundRefresh: false)) {
            // Given
            let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

            // When: Set up registry
            try await TuistTest.run(
                AccountUpdateCommand.self,
                ["--path", fixtureDirectory.pathString, "--handle", "tuistrocks"]
            )

            // Then
            #expect(ui().contains("""
            ✔ Success
              The account tuistrocks was successfully updated.
            """) == true)
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("generated_ios_app_with_frameworks")
    )
    func create_list_revoke_account_token() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let tokenName = "acceptance-test-token-\(UUID().uuidString.prefix(8).lowercased())"

        // When: Create an account token
        try await TuistTest.run(
            AccountTokensCreateCommand.self,
            [
                "tuist",
                "--path", fixtureDirectory.pathString,
                "--scopes", "project:cache:read",
                "--name", tokenName,
            ]
        )

        // Then: The token value is output
        let tokenOutput = Logger.testingLogHandler.collected[.info, ==]
        #expect(tokenOutput.isEmpty == false)

        // When: List account tokens
        try await TuistTest.run(
            AccountTokensListCommand.self,
            ["--path", fixtureDirectory.pathString, "tuist"]
        )

        // Then: The token is in the list
        // Checking just for prefix of the token since the table in acceptance tests is truncated
        #expect(ui().contains("accepta"))

        // When: Revoke the token
        try await TuistTest.run(
            AccountTokensRevokeCommand.self,
            ["--path", fixtureDirectory.pathString, "tuist", tokenName]
        )

        // Then: Success message is shown
        #expect(ui().contains("The account token '\(tokenName)' was successfully revoked."))

        resetUI()

        // When: List account tokens again
        try await TuistTest.run(
            AccountTokensListCommand.self,
            ["--path", fixtureDirectory.pathString, "tuist"]
        )

        // Then: The token is no longer in the list (either empty or doesn't contain the token name)
        #expect(ui().contains(tokenName) == false)
    }
}
