import Foundation
import Mockable
import Testing
import class TuistServer.MockServerSessionControlling

@testable import TuistApp

@Suite struct AppCredentialsServiceTests {
    private let subject: AppCredentialsService
    private let serverURLService: MockServerURLServicing
    private let appStorage: MockAppStoring
    private let serverSessionController: MockServerSessionControlling

    init() {
        serverURLService = MockServerURLServicing()
        appStorage = MockAppStoring()
        serverSessionController = MockServerSessionControlling()
        subject = AppCredentialsService(
            appStorage: appStorage,
            serverSessionController: serverSessionController,
            serverURLService: serverURLService
        )

        Matcher.register(AuthenticationStateKey.Type.self, match: { _, _ in true })
        Matcher.register(AuthenticationState.self, match: { $0 == $1 })

        given(serverURLService)
            .serverURL()
            .willReturn(.test())
    }

    @Test func test_load_initial_data_when_logged_out() {
        // Given
        given(appStorage)
            .get(.value(AuthenticationStateKey.self))
            .willReturn(.loggedOut)

        // When
        subject.loadCredentials()

        // Then
        #expect(subject.authenticationState == .loggedOut)
        #expect(subject.accountHandle == nil)
    }

    @Test func test_load_initial_data_when_logged_in() {
        // Given
        given(appStorage)
            .get(.value(AuthenticationStateKey.self))
            .willReturn(.loggedIn(accountHandle: "tuist"))

        // When
        subject.loadCredentials()

        // Then
        #expect(subject.authenticationState == .loggedIn(accountHandle: "tuist"))
        #expect(subject.accountHandle == "tuist")
    }

    @Test func test_login() async throws {
        // Given
        given(serverSessionController)
            .authenticate(
                serverURL: .any,
                deviceCodeType: .any,
                onOpeningBrowser: .any,
                onAuthWaitBegin: .any
            )
            .willReturn()

        given(serverSessionController)
            .whoami(serverURL: .any)
            .willReturn("tuist")

        given(appStorage)
            .set(.value(AuthenticationStateKey.self), value: .any)
            .willReturn()

        // When
        try await subject.login()

        // Then
        #expect(subject.authenticationState == .loggedIn(accountHandle: "tuist"))
        #expect(subject.accountHandle == "tuist")

        verify(appStorage)
            .set(.value(AuthenticationStateKey.self), value: .value(.loggedIn(accountHandle: "tuist")))
            .called(1)
    }

    @Test func test_logout() async throws {
        // Given
        given(serverSessionController)
            .logout(serverURL: .any)
            .willReturn()

        given(serverSessionController)
            .whoami(serverURL: .any)
            .willReturn(nil)

        given(appStorage)
            .set(.value(AuthenticationStateKey.self), value: .any)
            .willReturn()

        // When
        try await subject.logout()

        // Then
        #expect(subject.authenticationState == .loggedOut)

        verify(appStorage)
            .set(.value(AuthenticationStateKey.self), value: .value(.loggedOut))
            .called(1)
    }
}
