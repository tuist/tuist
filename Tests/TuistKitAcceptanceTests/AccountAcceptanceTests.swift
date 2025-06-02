import Foundation
import TuistAcceptanceTesting
import TuistServer
import TuistSupport
import TuistSupportTesting
import Testing

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
    
    @Test(
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH"]),
        .withMockedNoora,
        .withMockedLogger(forwardLogs: true),
        .withFixtureConnectedToCanary("ios_app_with_frameworks")
    )
    func account_with_organization_handle() async throws {
        // Given
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let fixtureAccountHandle = try #require(TuistTest.fixtureAccountHandle)
        let newHandle = String(UUID().uuidString.prefix(12).lowercased())
        
        // When: Set up registry
        try await TuistTest.run(
            AccountUpdateCommand.self,
            [fixtureAccountHandle, "--handle", newHandle, "--path", fixtureDirectory.pathString]
        )
        
        // Then
        #expect(ui().contains("""
            ✔ Success
              The account \(newHandle) was successfully updated.
            """) == true)
    }
}
