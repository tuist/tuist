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
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let updateAccountService = MockUpdateAccountServicing()
    private let serverAuthenticationController = MockServerAuthenticationControlling()
    private let serverSessionController = MockServerSessionControlling()

    init() {
        subject = AccountUpdateService(
            configLoader: configLoader,
            fileSystem: fileSystem,
            serverEnvironmentService: serverEnvironmentService,
            updateAccountService: updateAccountService,
            serverAuthenticationController: serverAuthenticationController,
            serverSessionController: serverSessionController
        )

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(.test())

        given(updateAccountService)
            .updateAccount(
                serverURL: .any,
                accountHandle: .any,
                handle: .any
            )
            .willReturn(.test())
        given(serverAuthenticationController).refreshToken(serverURL: .any).willReturn()
    }

    @Test func update_with_implicit_handle() async throws {
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

        given(serverAuthenticationController).refreshToken(serverURL: .any).willReturn()
    }

    @Test func update_with_explicit_handle() async throws {
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

        given(serverAuthenticationController).refreshToken(serverURL: .any).willReturn()
    }
}
