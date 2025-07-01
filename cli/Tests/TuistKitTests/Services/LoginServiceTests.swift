import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistTesting

final class LoginServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var authenticateService: MockAuthenticateServicing!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var userInputReader: MockUserInputReading!
    private var subject: LoginService!

    override func setUp() {
        super.setUp()
        serverSessionController = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        authenticateService = .init()
        serverEnvironmentService = .init()
        userInputReader = .init()
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
            authenticateService: authenticateService
        )
    }

    override func tearDown() {
        serverSessionController = nil
        configLoader = nil
        serverURL = nil
        authenticateService = nil
        serverEnvironmentService = nil
        userInputReader = nil
        subject = nil
        super.tearDown()
    }

    func test_run() async throws {
        // Given
        given(serverSessionController)
            .authenticate(
                serverURL: .value(serverURL),
                deviceCodeType: .any,
                onOpeningBrowser: .any,
                onAuthWaitBegin: .any
            )
            .willReturn(())

        // When / Then
        try await subject.run(
            email: nil,
            password: nil,
            directory: nil
        )
    }

    func test_authenticate_when_password_is_provided() async throws {
        try await withMockedDependencies {
            // Given
            given(userInputReader)
                .readString(asking: .value("Email:"))
                .willReturn("email@tuist.dev")
            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)

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
                    email: .value("email@tuist.dev"),
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
            try await subject.run(
                email: nil,
                password: "password",
                directory: nil
            )

            // Then
            XCTAssertEqual(
                ui(),
                """
                ✔ Success
                  Successfully logged in.
                """
            )
        }
    }

    func test_authenticate_when_email_is_provided() async throws {
        try await withMockedDependencies {
            // Given
            given(userInputReader)
                .readString(asking: .value("Password:"))
                .willReturn("password")

            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)

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
                    email: .value("email@tuist.dev"),
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
            try await subject.run(
                email: "email@tuist.dev",
                password: nil,
                directory: nil
            )

            // Then
            XCTAssertEqual(
                ui(),
                """
                ✔ Success
                  Successfully logged in.
                """
            )
        }
    }

    func test_authenticate_when_email_and_password_are_provided() async throws {
        try await withMockedDependencies {
            // Given
            let serverCredentialsStore = try XCTUnwrap(ServerCredentialsStore.mocked)
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
                    email: .value("email@tuist.dev"),
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
            try await subject.run(
                email: "email@tuist.dev",
                password: "password",
                directory: nil
            )

            // Then
            XCTAssertEqual(
                ui(),
                """
                ✔ Success
                  Successfully logged in.
                """
            )
            verify(userInputReader)
                .readString(asking: .any)
                .called(0)
        }
    }
}
