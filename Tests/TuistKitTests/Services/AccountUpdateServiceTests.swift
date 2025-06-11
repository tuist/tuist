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
    private let authTokenRefreshService = MockAuthTokenRefreshServicing()
    private let serverSessionController = MockServerSessionControlling()

    init() {
        subject = AccountUpdateService(
            configLoader: configLoader,
            fileSystem: fileSystem,
            serverURLService: serverURLService,
            updateAccountService: updateAccountService,
            authTokenRefreshService: authTokenRefreshService,
            serverSessionController: serverSessionController
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(.test())

        given(updateAccountService)
            .updateAccount(
                serverURL: .any,
                accountHandle: .any,
                handle: .any
            )
            .willReturn(.test())
        given(authTokenRefreshService).refreshTokens(serverURL: .any).willReturn()
    }

    @Test func test_update_with_implicit_handle() async throws {
        // Given
        given(serverSessionController).authenticatedHandle(serverURL: .any).willReturn("tuistrocks")

        // When
        try await subject.run(
            accountHandle: nil,
            handle: "newhandle",
            directory: nil
        )

        // Then
        verify(updateAccountService).updateAccount(
            serverURL: .any,
            accountHandle: .value("tuistrocks"),
            handle: .value("newhandle")
        ).called(1)

        verify(authTokenRefreshService).refreshTokens(
            serverURL: .any
        ).called(1)
    }

    @Test func test_update_with_explicit_handle() async throws {
        // Given
        given(serverSessionController).authenticatedHandle(serverURL: .any).willReturn("tuistrocks")

        // When
        try await subject.run(
            accountHandle: "foo",
            handle: "newhandle",
            directory: nil
        )

        // Then
        verify(updateAccountService).updateAccount(
            serverURL: .any, accountHandle: .value("foo"), handle: .value("newhandle")
        )
        .called(1)

        verify(authTokenRefreshService).refreshTokens(
            serverURL: .any
        ).called(1)
    }
}
