import Foundation
import Mockable
import Testing
import TuistCore
import TuistEnvironment
import TuistOIDC
import TuistServer
import TuistSupport
import TuistUserInputReader

@testable import TuistAuthCommand
@testable import TuistTesting

struct LoginCommandServiceEnvTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let serverSessionController: MockServerSessionControlling
    private let serverEnvironmentService: MockServerEnvironmentServicing
    private let userInputReader: MockUserInputReading
    private let authenticateService: MockAuthenticateServicing
    private let ciOIDCAuthenticator: MockCIOIDCAuthenticating
    private let exchangeOIDCTokenService: MockExchangeOIDCTokenServicing
    private let subject: LoginCommandService

    init() {
        serverSessionController = MockServerSessionControlling()
        serverEnvironmentService = MockServerEnvironmentServicing()
        userInputReader = MockUserInputReading()
        authenticateService = MockAuthenticateServicing()
        ciOIDCAuthenticator = MockCIOIDCAuthenticating()
        exchangeOIDCTokenService = MockExchangeOIDCTokenServicing()

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        subject = LoginCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverSessionController: serverSessionController,
            userInputReader: userInputReader,
            authenticateService: authenticateService,
            ciOIDCAuthenticator: ciOIDCAuthenticator,
            exchangeOIDCTokenService: exchangeOIDCTokenService
        )
    }

    @Test(.withMockedEnvironment())
    func run_uses_tuist_url_env_variable_when_no_server_url_argument() async throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_URL"] = "https://env.tuist.dev"

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
            serverURL: nil
        )

        // Then
        verify(serverEnvironmentService)
            .url(configServerURL: .value(URL(string: "https://env.tuist.dev")!))
            .called(1)
    }
}
