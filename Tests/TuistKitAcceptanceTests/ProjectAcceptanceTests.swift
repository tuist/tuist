import Foundation
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit
@testable import TuistServer

final class ProjectAcceptanceTestProjects: ServerAcceptanceTestCase {
    func test_list_project() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(ProjectListCommand.self)
        XCTAssertStandardOutput(pattern: "Listing all your projects:")
        XCTAssertStandardOutput(pattern: "• \(fullHandle)")
    }
}

final class ProjectAcceptanceTestProjectTokens: ServerAcceptanceTestCase {
    func test_create_list_and_revoke_project_token() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
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

final class ProjectAcceptanceTestProjectDefaultBranch: ServerAcceptanceTestCase {
    func test_update_default_branch() async throws {
        try await setUpFixture(.iosAppWithFrameworks)
        try await run(ProjectShowCommand.self, fullHandle)
        XCTAssertStandardOutput(
            pattern: """
            Full handle: \(fullHandle)
            Default branch: main
            """
        )
        try await run(ProjectUpdateCommand.self, fullHandle, "--default-branch", "new-default-branch")
        TestingLogHandler.reset()
        try await run(ProjectShowCommand.self, fullHandle)
        XCTAssertStandardOutput(
            pattern: """
            Full handle: \(fullHandle)
            Default branch: new-default-branch
            """
        )
    }
}
