import Foundation
import TuistAcceptanceTesting
import XCTest

@testable import TuistKit
@testable import TuistServer

final class ServerAcceptanceTestProjects: TuistAcceptanceTestCase {
    func test_create_and_delete_organization_with_project() async throws {
        try setUpFixture(.iosAppWithFrameworks)
        let organizationHandle = String(UUID().uuidString.prefix(12).lowercased())
        let projectHandle = String(UUID().uuidString.prefix(12).lowercased())
        let fullHandle = "\(organizationHandle)/\(projectHandle)"
        try await run(OrganizationCreateCommand.self, organizationHandle)
        try await run(ProjectCreateCommand.self, fullHandle)
        try await run(ProjectListCommand.self)
        try await run(ProjectDeleteCommand.self, fullHandle)
        try await run(OrganizationDeleteCommand.self, organizationHandle)
        XCTAssertStandardOutput(pattern: "Listing all your projects:")
        XCTAssertStandardOutput(pattern: "• \(fullHandle)")
    }
}
