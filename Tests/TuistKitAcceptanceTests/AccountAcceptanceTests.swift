import Foundation
import TuistAcceptanceTesting
import TuistServer
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

final class AccountAcceptanceTests: ServerAcceptanceTestCase {
    func test_update_account_with_logged_in_user() async throws {
        try await withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(AccountUpdateCommand.self, "--handle", "tuistrocks")

            let got = ui()
            let expectedOutput = """
            ✔ Success
              The account tuistrocks was successfully updated.
            """

            XCTAssertEqual(got, expectedOutput)
        }
    }

    func test_update_account_with_organization_handle() async throws {
        try await withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            let newHandle = String(UUID().uuidString.prefix(12).lowercased())
            try await run(AccountUpdateCommand.self, organizationHandle, "--handle", newHandle)

            let got = ui()
            let expectedOutput = """
            ✔ Success
              The account \(newHandle) was successfully updated.
            """

            XCTAssertEqual(got, expectedOutput)

            // Update handles for teardown function.
            self.organizationHandle = newHandle
            self.fullHandle = "\(newHandle)/\(projectHandle)"
        }
    }
}
