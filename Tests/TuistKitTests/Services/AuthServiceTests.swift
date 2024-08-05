import Foundation
import MockableTest
import Path
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class AuthServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var authenticateService: MockAuthenticateServicing!
    private var serverCredentialsStore: MockServerCredentialsStoring!
    private var serverURLService: MockServerURLServicing!
    private var userInputReader: MockUserInputReading!
    private var subject: AuthService!

    override func setUp() {
        super.setUp()
        serverSessionController = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        authenticateService = .init()
        serverCredentialsStore = .init()
        serverURLService = .init()
        userInputReader = .init()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(url: serverURL))

        given(serverURLService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        subject = AuthService(
            serverSessionController: serverSessionController,
            serverURLService: serverURLService,
            configLoader: configLoader,
            userInputReader: userInputReader,
            authenticateService: authenticateService,
            serverCredentialsStore: serverCredentialsStore
        )
    }

    override func tearDown() {
        serverSessionController = nil
        configLoader = nil
        serverURL = nil
        authenticateService = nil
        serverCredentialsStore = nil
        serverURLService = nil
        userInputReader = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate() async throws {
        // Given
        given(serverSessionController)
            .authenticate(serverURL: .value(serverURL))
            .willReturn(())

        // When / Then
        try await subject.authenticate(
            email: nil,
            password: nil,
            directory: nil
        )
    }

    func test_authenticate_when_password_is_provided() async throws {
        // Given
        given(userInputReader)
            .readString(asking: .value("Email:"))
            .willReturn("email@tuist.io")

        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        token: nil,
                        accessToken: "access-token",
                        refreshToken: "refresh-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        given(authenticateService)
            .authenticate(
                email: .value("email@tuist.io"),
                password: .value("password"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                ServerAuthenticationTokens(
                    accessToken: "access-token",
                    refreshToken: "refresh-token"
                )
            )

        // When
        try await subject.authenticate(
            email: nil,
            password: "password",
            directory: nil
        )

        // Then
        XCTAssertStandardOutput(pattern: "Credentials stored successfully.")
    }

    func test_authenticate_when_email_is_provided() async throws {
        // Given
        given(userInputReader)
            .readString(asking: .value("Password:"))
            .willReturn("password")

        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        token: nil,
                        accessToken: "access-token",
                        refreshToken: "refresh-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        given(authenticateService)
            .authenticate(
                email: .value("email@tuist.io"),
                password: .value("password"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                ServerAuthenticationTokens(
                    accessToken: "access-token",
                    refreshToken: "refresh-token"
                )
            )

        // When
        try await subject.authenticate(
            email: "email@tuist.io",
            password: nil,
            directory: nil
        )

        // Then
        XCTAssertStandardOutput(pattern: "Credentials stored successfully.")
    }

    func test_authenticate_when_email_and_password_are_provided() async throws {
        // Given
        given(serverCredentialsStore)
            .store(
                credentials: .value(
                    ServerCredentials(
                        token: nil,
                        accessToken: "access-token",
                        refreshToken: "refresh-token"
                    )
                ),
                serverURL: .any
            )
            .willReturn()

        given(authenticateService)
            .authenticate(
                email: .value("email@tuist.io"),
                password: .value("password"),
                serverURL: .value(serverURL)
            )
            .willReturn(
                ServerAuthenticationTokens(
                    accessToken: "access-token",
                    refreshToken: "refresh-token"
                )
            )

        // When
        try await subject.authenticate(
            email: "email@tuist.io",
            password: "password",
            directory: nil
        )

        // Then
        XCTAssertStandardOutput(pattern: "Credentials stored successfully.")
        verify(userInputReader)
            .readString(asking: .any)
            .called(0)
    }
}
