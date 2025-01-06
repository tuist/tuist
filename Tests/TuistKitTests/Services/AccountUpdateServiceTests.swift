import FileSystem
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport

@testable import TuistKit

struct AccountUpdateServiceTests {
    private let subject: AccountUpdateService
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let serverURLService = MockServerURLServicing()
    private let updateAccountService = MockUpdateAccountServicing()
    private let refreshAuthTokenService = MockRefreshAuthTokenServicing()
    private let serverSessionController = MockServerSessionControlling()
    private let serverAuthenticationController = MockServerAuthenticationControlling()

    init() {
        subject = AccountUpdateService(
            configLoader: configLoader,
            fileSystem: fileSystem,
            serverURLService: serverURLService,
            updateAccountService: updateAccountService,
            refreshAuthTokenService: refreshAuthTokenService,
            serverSessionController: serverSessionController,
            serverAuthenticationController: serverAuthenticationController
        )
    }

    @Test func test_update_with_valid_handle() async throws {
        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(.test())

        given(serverSessionController).whoami(serverURL: .any).willReturn("tuistrocks")
        given(updateAccountService)
            .updateAccount(
                serverURL: .any,
                accountHandle: .value("tuistrocks"),
                handle: .value("foo")
            )
            .willReturn(.test())

        // When
        try await subject.run(
            accountHandle: nil,
            handle: "foo",
            directory: nil
        )
    }
}
