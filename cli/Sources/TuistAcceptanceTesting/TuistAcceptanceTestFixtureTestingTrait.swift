import ArgumentParser
import FileSystem
import Foundation
import Path
import Testing
import TuistSupport
import TuistTesting
@testable import TuistKit

public struct TuistAcceptanceTestFixtureTestingTrait: TestTrait, SuiteTrait, TestScoping {
    let fixtureDirectory: AbsolutePath

    init(fixture: String, fixturesDirectory: AbsolutePath = Fixtures.directory) {
        fixtureDirectory = fixturesDirectory.appending(component: fixture)
    }

    public func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        let fileSystem = FileSystem()
        let organizationHandle = String(UUID().uuidString.prefix(12).lowercased())
        let projectHandle = String(UUID().uuidString.prefix(12).lowercased())
        let fullHandle = "\(organizationHandle)/\(projectHandle)"
        let email = try #require(ProcessInfo.processInfo.environment[EnvKey.authEmail.rawValue])
        let password = try #require(ProcessInfo.processInfo.environment[EnvKey.authPassword.rawValue])

        try await fileSystem.runInTemporaryDirectory { temporaryDirectory in
            let existingEnvVariables = Environment.current.variables

            try await TuistTesting
                .withMockedEnvironment(temporaryDirectory: temporaryDirectory.appending(component: "environment")) {
                    existingEnvVariables.forEach { Environment.mocked?.variables[$0.key] = $0.value }

                    let fixtureTemporaryDirectory = temporaryDirectory.appending(
                        component: fixtureDirectory.basename
                    )
                    try await fileSystem.copy(fixtureDirectory, to: fixtureTemporaryDirectory)
                    try await TuistTest.$fixtureDirectory.withValue(fixtureTemporaryDirectory) {
                        try await TuistTest.$fixtureAccountHandle.withValue(organizationHandle) {
                            try await TuistTest.$fixtureFullHandle.withValue(fullHandle) {
                                try await TuistTest.run(
                                    LoginCommand.self,
                                    ["--email", email, "--password", password, "--path", fixtureTemporaryDirectory.pathString]
                                )
                                try await TuistTest.run(
                                    OrganizationCreateCommand.self,
                                    [organizationHandle, "--path", fixtureTemporaryDirectory.pathString]
                                )
                                try await TuistTest.run(
                                    ProjectCreateCommand.self,
                                    [fullHandle, "--path", fixtureTemporaryDirectory.pathString]
                                )

                                try await fileSystem.writeText(
                                    """
                                    import ProjectDescription

                                    let tuist = Tuist(
                                        fullHandle: "\(fullHandle)",
                                        url: "\(Environment.current.variables["TUIST_URL"] ?? "https://canary.tuist.dev")"
                                    )
                                    """,
                                    at: fixtureTemporaryDirectory.appending(components: "Tuist.swift"),
                                    options: Set([.overwrite])
                                )
                                resetUI()

                                let revert = {
                                    try await TuistTest.run(
                                        ProjectDeleteCommand.self,
                                        [fullHandle, "--path", fixtureTemporaryDirectory.pathString]
                                    )
                                    try await TuistTest.run(
                                        OrganizationDeleteCommand.self,
                                        [organizationHandle, "--path", fixtureTemporaryDirectory.pathString]
                                    )
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
        fixturesDirectory: AbsolutePath = Fixtures.directory
    ) -> Self {
        return Self(fixture: fixture, fixturesDirectory: fixturesDirectory)
    }
}
