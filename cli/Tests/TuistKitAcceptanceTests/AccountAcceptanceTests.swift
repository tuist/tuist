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
        .withFixtureConnectedToCanary("ios_app_with_frameworks")
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
}
