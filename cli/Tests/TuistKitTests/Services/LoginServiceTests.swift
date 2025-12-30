import Foundation
import Mockable
import Testing
import TuistCore
import TuistLoader
import TuistOIDC
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct LoginServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let serverSessionController: MockServerSessionControlling
    private let configLoader: MockConfigLoading
    private let serverEnvironmentService: MockServerEnvironmentServicing
    private let userInputReader: MockUserInputReading
    private let authenticateService: MockAuthenticateServicing
    private let ciOIDCAuthenticator: MockCIOIDCAuthenticating
    private let exchangeOIDCTokenService: MockExchangeOIDCTokenServicing
    private let subject: LoginService

    init() {
        serverSessionController = MockServerSessionControlling()
        configLoader = MockConfigLoading()
        serverEnvironmentService = MockServerEnvironmentServicing()
        userInputReader = MockUserInputReading()
        authenticateService = MockAuthenticateServicing()
        ciOIDCAuthenticator = MockCIOIDCAuthenticating()
        exchangeOIDCTokenService = MockExchangeOIDCTokenServicing()

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        subject = LoginService(
            serverSessionController: serverSessionController,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader,
            userInputReader: userInputReader,
            authenticateService: authenticateService,
            ciOIDCAuthenticator: ciOIDCAuthenticator,
            exchangeOIDCTokenService: exchangeOIDCTokenService
        )
    }

    @Test
    func run_authenticates_with_browser() async throws {
        // Given
        given(serverSessionController)
            .authenticate(
                serverURL: .any,
                deviceCodeType: .any,
                onOpeningBrowser: .any,
                onAuthWaitBegin: .any
            )
            .willReturn(())

        // When
        try await subject.run(
            email: nil,
            password: nil,
            directory: nil
        )

        // Then
        verify(serverSessionController)
            .authenticate(
                serverURL: .any,
                deviceCodeType: .any,
                onOpeningBrowser: .any,
                onAuthWaitBegin: .any
            )
            .called(1)
    }

    @Test(.withMockedDependencies())
    func authenticate_when_password_is_provided() async throws {
        // Given
        given(userInputReader)
            .readString(asking: .value("Email:"))
            .willReturn("email@tuist.dev")

        let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        given(authenticateService)
            .authenticate(
                email: .value("email@tuist.dev"),
                password: .value("password"),
                serverURL: .any
            )
            .willReturn(
                ServerAuthenticationTokens(
                    accessToken: "access-token",
                    refreshToken: "refresh-token"
                )
            )

        // When
        try await subject.run(
            email: nil,
            password: "password",
            directory: nil
        )

        // Then
        verify(authenticateService)
            .authenticate(
                email: .value("email@tuist.dev"),
                password: .value("password"),
                serverURL: .any
            )
            .called(1)
    }

    @Test(.withMockedDependencies())
    func authenticate_when_email_is_provided() async throws {
        // Given
        given(userInputReader)
            .readString(asking: .value("Password:"))
            .willReturn("password")

        let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        given(authenticateService)
            .authenticate(
                email: .value("email@tuist.dev"),
                password: .value("password"),
                serverURL: .any
            )
            .willReturn(
                ServerAuthenticationTokens(
                    accessToken: "access-token",
                    refreshToken: "refresh-token"
                )
            )

        // When
        try await subject.run(
            email: "email@tuist.dev",
            password: nil,
            directory: nil
        )

        // Then
        verify(authenticateService)
            .authenticate(
                email: .value("email@tuist.dev"),
                password: .value("password"),
                serverURL: .any
            )
            .called(1)
    }

    @Test(.withMockedDependencies())
    func authenticate_when_email_and_password_are_provided() async throws {
        // Given
        let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        accessToken: "access-token",
                        refreshToken: "refresh-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        given(authenticateService)
            .authenticate(
                email: .value("email@tuist.dev"),
                password: .value("password"),
                serverURL: .any
            )
            .willReturn(
                ServerAuthenticationTokens(
                    accessToken: "access-token",
                    refreshToken: "refresh-token"
                )
            )

        // When
        try await subject.run(
            email: "email@tuist.dev",
            password: "password",
            directory: nil
        )

        // Then
        verify(userInputReader)
            .readString(asking: .any)
            .called(0)

        verify(authenticateService)
            .authenticate(
                email: .value("email@tuist.dev"),
                password: .value("password"),
                serverURL: .any
            )
            .called(1)
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies())
    func authenticate_with_oidc_in_ci_environment() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables["CI"] = "1"

        given(ciOIDCAuthenticator)
            .fetchOIDCToken()
            .willReturn("oidc-jwt-token")

        given(exchangeOIDCTokenService)
            .exchangeOIDCToken(oidcToken: .value("oidc-jwt-token"), serverURL: .any)
            .willReturn("tuist-access-token")

        let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        accessToken: "tuist-access-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        // When
        try await subject.run(
            email: nil,
            password: nil,
            directory: nil
        )

        // Then
        verify(ciOIDCAuthenticator)
            .fetchOIDCToken()
            .called(1)

        verify(exchangeOIDCTokenService)
            .exchangeOIDCToken(oidcToken: .value("oidc-jwt-token"), serverURL: .any)
            .called(1)

        verify(serverSessionController)
            .authenticate(serverURL: .any, deviceCodeType: .any, onOpeningBrowser: .any, onAuthWaitBegin: .any)
            .called(0)
    }
}
