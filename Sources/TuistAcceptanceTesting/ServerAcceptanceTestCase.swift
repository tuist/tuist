import Foundation
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

open class ServerAcceptanceTestCase: TuistAcceptanceTestCase {
    public var fullHandle: String = ""
    public var organizationHandle: String = ""
    public var projectHandle: String = ""

    override public func setUpFixture(_ fixture: TuistAcceptanceFixtures) async throws {
        try await super.setUpFixture(fixture)
        organizationHandle = String(UUID().uuidString.prefix(12).lowercased())
        projectHandle = String(UUID().uuidString.prefix(12).lowercased())
        fullHandle = "\(organizationHandle)/\(projectHandle)"
        let email = try XCTUnwrap(ProcessInfo.processInfo.environment[EnvKey.authEmail.rawValue])
        let password = try XCTUnwrap(ProcessInfo.processInfo.environment[EnvKey.authPassword.rawValue])
        try await run(AuthCommand.self, "--email", email, "--password", password)
        try await run(OrganizationCreateCommand.self, organizationHandle)
        try await run(ProjectCreateCommand.self, fullHandle)
        try FileHandler.shared.write(
            """
            import ProjectDescription

            let config = Config(
                fullHandle: "\(fullHandle)",
                url: "\(ProcessInfo.processInfo.environment["TUIST_URL"] ?? "https://canary.tuist.io")"
            )
            """,
            path: fixturePath.appending(components: "Tuist", "Config.swift"),
            atomically: true
        )
    }

    override open func tearDown() async throws {
        try await run(ProjectDeleteCommand.self, fullHandle)
        try await run(OrganizationDeleteCommand.self, organizationHandle)
        try await run(LogoutCommand.self)
        TestingLogHandler.reset()
        try await super.tearDown()
    }
}
