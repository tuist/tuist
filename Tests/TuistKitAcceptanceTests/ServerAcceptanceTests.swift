import Foundation
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit
@testable import TuistServer

final class ServerAcceptanceTestProjects: ServerAcceptanceTestCase {
    func test_list_project() async throws {
        try await run(ProjectListCommand.self)
        XCTAssertStandardOutput(pattern: "Listing all your projects:")
        XCTAssertStandardOutput(pattern: "• \(fullHandle)")
    }
}

final class ServerAcceptanceTestProjectTokens: ServerAcceptanceTestCase {
    func test_create_list_and_revoke_project_token() async throws {
        try await run(ProjectTokensCreateCommand.self, fullHandle)
        TestingLogHandler.reset()
        try await run(ProjectTokensListCommand.self, fullHandle)
        let id = try XCTUnwrap(
            TestingLogHandler.collected[.info, <=]
                .components(separatedBy: .newlines)
                .dropLast().last?
                .components(separatedBy: .whitespaces)
                .first
        )
        try await run(ProjectTokensRevokeCommand.self, id, fullHandle)
        TestingLogHandler.reset()
        try await run(ProjectTokensListCommand.self, fullHandle)
        XCTAssertStandardOutput(
            pattern: "No project tokens found. Create one by running `tuist project tokens create \(fullHandle)."
        )
    }
}

// MARK: - Helpers

class ServerAcceptanceTestCase: TuistAcceptanceTestCase {
    var fullHandle: String = ""
    var organizationHandle: String = ""
    var projectHandle: String = ""

    override func setUp() async throws {
        try await super.setUp()
        try setUpFixture(.iosAppWithFrameworks)
        organizationHandle = String(UUID().uuidString.prefix(12).lowercased())
        projectHandle = String(UUID().uuidString.prefix(12).lowercased())
        fullHandle = "\(organizationHandle)/\(projectHandle)"
        let email = try XCTUnwrap(ProcessInfo.processInfo.environment[EnvKey.authEmail.rawValue])
        let password = try XCTUnwrap(ProcessInfo.processInfo.environment[EnvKey.authPassword.rawValue])
        try await run(AuthCommand.self, "--email", email, "--password", password)
        try await run(OrganizationCreateCommand.self, organizationHandle)
        try await run(ProjectCreateCommand.self, fullHandle)
    }

    override func tearDown() async throws {
        try await run(ProjectDeleteCommand.self, fullHandle)
        try await run(OrganizationDeleteCommand.self, organizationHandle)
        try run(LogoutCommand.self)
        try await super.tearDown()
    }
}
