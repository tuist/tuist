import Foundation
import ServiceContextModule
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit
@testable import TuistServer

final class AccountAcceptanceTestProjects: ServerAcceptanceTestCase {
    func test_update_account_with_logged_in_user() async throws {
        try await ServiceContext.withTestingDependencies {
            try await setUpFixture(.iosAppWithFrameworks)
            try await run(AccountUpdateCommand.self, "--handle", "new-handle")
            XCTAssertStandardOutput(pattern: "The account new-handle was successfully updated.")
        }
    }
}
