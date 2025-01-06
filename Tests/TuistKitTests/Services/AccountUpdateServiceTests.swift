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

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(.test())

        given(serverAuthenticationController).authenticationToken(serverURL: .any).willReturn(.user(
            legacyToken: nil,
            accessToken: .test(),
            refreshToken: .test()
        ))
        given(updateAccountService)
            .updateAccount(
                serverURL: .any,
                accountHandle: .any,
                handle: .any
            )
            .willReturn(.test())
        given(refreshAuthTokenService).refreshTokens(serverURL: .any, refreshToken: .value("token")).willReturn(.init(accessToken:
            "new-access-token", refreshToken: "new-refresh-token"))
    }

    @Test func test_update_with_implicit_handle() async throws {
        // Given
        given(serverSessionController).whoami(serverURL: .any).willReturn("tuistrocks")

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

        verify(refreshAuthTokenService).refreshTokens(
            serverURL: .any,
            refreshToken: .value("token")
        ).called(1)
    }

    @Test func test_update_with_explicit_handle() async throws {
        // Given
        given(serverSessionController).whoami(serverURL: .any).willReturn("tuistrocks")

        // When
        try await subject.run(
            accountHandle: "foo",
            handle: "newhandle",
            directory: nil
        )

        // Then
        verify(updateAccountService).updateAccount(serverURL: .any, accountHandle: .value("foo"), handle: .value("newhandle"))
            .called(1)

        verify(refreshAuthTokenService).refreshTokens(
            serverURL: .any,
            refreshToken: .value("token")
        ).called(1)
    }

    @Test func test_not_logged_in() async throws {
        // Given
        given(serverSessionController).whoami(serverURL: .any).willReturn(nil)

        await #expect(throws: AccountUpdateServiceError.missingHandle) {
            // Then
            try await subject.run(
                accountHandle: nil,
                handle: "newhandle",
                directory: nil
            )
        }
    }
}
