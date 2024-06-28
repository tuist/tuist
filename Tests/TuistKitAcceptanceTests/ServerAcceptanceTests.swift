import Foundation
import TuistAcceptanceTesting
import XCTest

@testable import TuistServer
@testable import TuistKit

final class ServerAcceptanceTestProjects: TuistAcceptanceTestCase {
    func test_create_and_delete_organization_with_project() async throws {
        try setUpFixture(.iosAppWithFrameworks)
        let organizationName = String(UUID().uuidString.prefix(12).lowercased())
        let projectName = String(UUID().uuidString.prefix(12).lowercased())
        try await run(CloudOrganizationCreateCommand.self, organizationName)
        try await run(CloudProjectCreateCommand.self, projectName, "--organization", organizationName)
        try await run(CloudProjectListCommand.self)
        try await run(CloudProjectDeleteCommand.self, projectName, "--organization", organizationName)
        try await run(CloudOrganizationDeleteCommand.self, organizationName)
        XCTAssertStandardOutput(pattern: "Listing all your projects:")
        XCTAssertStandardOutput(pattern: "• \(organizationName)/\(projectName)")
    }
}
