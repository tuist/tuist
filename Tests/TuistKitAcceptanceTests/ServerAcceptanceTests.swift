import Foundation
import TuistAcceptanceTesting
import XCTest

@testable import TuistKit
@testable import TuistServer

final class ServerAcceptanceTestProjects: TuistAcceptanceTestCase {
    func test_create_and_delete_organization_with_project() async throws {
        try setUpFixture(.iosAppWithFrameworks)
        let organizationName = String(UUID().uuidString.prefix(12).lowercased())
        let projectName = String(UUID().uuidString.prefix(12).lowercased())
        try await run(OrganizationCreateCommand.self, organizationName)
        try await run(ProjectCreateCommand.self, projectName, "--organization", organizationName)
        try await run(ProjectListCommand.self)
        try await run(ProjectDeleteCommand.self, projectName, "--organization", organizationName)
        try await run(OrganizationDeleteCommand.self, organizationName)
        XCTAssertStandardOutput(pattern: "Listing all your projects:")
        XCTAssertStandardOutput(pattern: "• \(organizationName)/\(projectName)")
    }
}
