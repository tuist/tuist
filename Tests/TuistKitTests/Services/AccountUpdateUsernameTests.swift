import Foundation
import Mockable
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting

@testable import TuistKit

final class AccountUpdateUsernameServiceTests: TuistUnitTestCase {
    private var configLoader: MockConfigLoading!
    private var updateAccountUsernameService: MockUpdateAccountUsernameServicing!
    private var subject: AccountUpdateUsernameService!
    private var serverURL: URL!

    override func setUp() async throws {
        try await super.setUp()

        configLoader = MockConfigLoading()

        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))

        updateAccountUsernameService = MockUpdateAccountUsernameServicing()
        subject = AccountUpdateUsernameService(
            updateAccountUsernameService: updateAccountUsernameService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        configLoader = nil
        updateAccountUsernameService = nil
        subject = nil
        serverURL = nil
        super.tearDown()
    }

    func test_update_with_valid_username() async throws {
        given(updateAccountUsernameService)
            .updateAccountUsername(
                serverURL: .value(serverURL),
                name: .value("tuistrocks")
            )
            .willReturn("tuistrocks")

        // When
        try await subject.run(
            name: "tuistrocks",
            directory: nil
        )

        XCTAssertPrinterOutputContains("""
        Successfully updated username to tuistrocks.
        """)
    }
}
