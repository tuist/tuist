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
        try await run(CloudOrganizationCreateCommand.self, organizationHandle)
        try await run(CloudProjectCreateCommand.self, fullHandle)
        try await run(CloudProjectListCommand.self)
        try await run(CloudProjectDeleteCommand.self, fullHandle)
        try await run(CloudOrganizationDeleteCommand.self, organizationHandle)
        XCTAssertStandardOutput(pattern: "Listing all your projects:")
        XCTAssertStandardOutput(pattern: "• \(fullHandle)")
    }
}
