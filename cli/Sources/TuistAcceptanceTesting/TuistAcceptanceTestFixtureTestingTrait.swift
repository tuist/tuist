import ArgumentParser
import FileSystem
import Foundation
import Path
import Testing
import TuistAuthCommand
import TuistEnvironment
import TuistEnvironmentTesting
import TuistEnvKey
import TuistNooraTesting
@_exported import TuistOrganizationCommand
@_exported import TuistProjectCommand
import TuistSupport
import TuistTesting
@testable import TuistKit

public struct TuistAcceptanceTestFixtureTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let fixtureDirectory: AbsolutePath
    let accountHandle: String?

    init(fixture: String, fixturesDirectory: AbsolutePath = Fixtures.directory, accountHandle: String? = nil) {
        fixtureDirectory = fixturesDirectory.appending(component: fixture)
        self.accountHandle = accountHandle
    }

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let fileSystem = FileSystem()
        let fixtureAccountHandle = accountHandle ?? String(UUID().uuidString.prefix(12).lowercased())
        let projectHandle = String(UUID().uuidString.prefix(12).lowercased())
        let fullHandle = "\(fixtureAccountHandle)/\(projectHandle)"
        let createsOrganization = accountHandle == nil
        let email = try #require(ProcessInfo.processInfo.environment[EnvKey.authEmail.rawValue])
        let password = try #require(ProcessInfo.processInfo.environment[EnvKey.authPassword.rawValue])

        try await fileSystem.runInTemporaryDirectory { temporaryDirectory in
            let existingEnvVariables = Environment.current.variables

            try await TuistEnvironmentTesting
                .withMockedEnvironment {
                    existingEnvVariables
                        .forEach { Environment.mocked?.variables[$0.key] = $0.value }

                    let fixtureTemporaryDirectory = temporaryDirectory.appending(
                        component: fixtureDirectory.basename
                    )
                    try await fileSystem.copy(fixtureDirectory, to: fixtureTemporaryDirectory)
                    try await TuistTest.$fixtureDirectory.withValue(fixtureTemporaryDirectory) {
                        try await TuistTest.$fixtureAccountHandle.withValue(fixtureAccountHandle) {
                            try await TuistTest.$fixtureFullHandle.withValue(fullHandle) {
                                let serverURL = Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev"

                                try await fileSystem.writeText(
                                    """
                                    import ProjectDescription

                                    let tuist = Tuist(
                                        fullHandle: "\(fullHandle)",
                                        url: "\(serverURL)"
                                    )
                                    """,
                                    at: fixtureTemporaryDirectory.appending(components: "Tuist.swift"),
                                    options: Set([.overwrite])
                                )

                                try await TuistTest.run(
                                    LoginCommand.self,
                                    [
                                        "--email",
                                        email,
                                        "--password",
                                        password,
                                        "--url",
                                        serverURL,
                                    ]
                                )
                                if createsOrganization {
                                    try await TuistTest.run(
                                        OrganizationCreateCommand.self,
                                        [fixtureAccountHandle, "--path", fixtureTemporaryDirectory.pathString]
                                    )
                                }
                                try await TuistTest.run(
                                    ProjectCreateCommand.self,
                                    [fullHandle, "--path", fixtureTemporaryDirectory.pathString, "--build-system", "xcode"]
                                )
                                resetUI()

                                let revert = {
                                    try await TuistTest.run(
                                        ProjectDeleteCommand.self,
                                        [fullHandle, "--path", fixtureTemporaryDirectory.pathString]
                                    )
                                    if createsOrganization {
                                        try await TuistTest.run(
                                            OrganizationDeleteCommand.self,
                                            [fixtureAccountHandle, "--path", fixtureTemporaryDirectory.pathString]
                                        )
                                    }
                                    try await TuistTest.run(
                                        LogoutCommand.self
                                    )
                                }

                                do {
                                    try await function()
                                } catch {
                                    try await revert()
                                    throw error
                                }
                                try await revert()
                            }
                        }
                    }
                }
        }
    }
}

extension Trait where Self == TuistAcceptanceTestFixtureTestingTrait {
    public static func withFixtureConnectedToCanary(
        _ fixture: String,
        fixturesDirectory: AbsolutePath = Fixtures.directory,
        accountHandle: String? = nil
    ) -> Self {
        return Self(fixture: fixture, fixturesDirectory: fixturesDirectory, accountHandle: accountHandle)
    }
}
