import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import TuistServer
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class AccountAcceptanceTests: ServerAcceptanceTestCase {
    func test_update_account_with_logged_in_user() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(AccountUpdateCommand.self, "--handle", "tuistrocks")
            XCTAssertStandardOutput(pattern: "The account tuistrocks was successfully updated.")
        }
    }

    func test_update_account_with_organization_handle() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            let newHandle = String(UUID().uuidString.prefix(12).lowercased())
            try await run(AccountUpdateCommand.self, organizationHandle, "--handle", newHandle)

            XCTAssertStandardOutput(pattern: "The account \(newHandle) was successfully updated.")

            // Update handles for teardown function.
            self.organizationHandle = newHandle
            self.fullHandle = "\(newHandle)/\(projectHandle)"
        }
    }
}
