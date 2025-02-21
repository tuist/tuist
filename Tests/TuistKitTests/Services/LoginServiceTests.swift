import Foundation
import Mockable
import ServiceContextModule
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistServer
import TuistSupport
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class LoginServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!
    private var authenticateService: MockAuthenticateServicing!
    private var serverCredentialsStore: MockServerCredentialsStoring!
    private var serverURLService: MockServerURLServicing!
    private var userInputReader: MockUserInputReading!
    private var subject: LoginService!

    override func setUp() {
        super.setUp()
        serverSessionController = .init()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
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

        subject = LoginService(
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
        try await ServiceContext.withTestingDependencies {
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
            try await subject.run(
                email: nil,
                password: "password",
                directory: nil
            )

            // Then
            let output = ServiceContext.current?.recordedUI()
            let expectedOutput = """
            stdout: ▌ ✔ Success
            stdout: ▌ Successfully logged in.
            """
            XCTAssertEqual(output, expectedOutput)
        }
    }

    func test_authenticate_when_email_is_provided() async throws {
        try await ServiceContext.withTestingDependencies {
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
            try await subject.run(
                email: "email@tuist.io",
                password: nil,
                directory: nil
            )

            // Then
            let output = ServiceContext.current?.recordedUI()
            let expectedOutput = """
            stdout: ▌ ✔ Success
            stdout: ▌ Successfully logged in.
            """
            XCTAssertEqual(output, expectedOutput)
        }
    }

    func test_authenticate_when_email_and_password_are_provided() async throws {
        try await ServiceContext.withTestingDependencies {
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
            try await subject.run(
                email: "email@tuist.io",
                password: "password",
                directory: nil
            )

            // Then
            let output = ServiceContext.current?.recordedUI()
            let expectedOutput = """
            stdout: ▌ ✔ Success
            stdout: ▌ Successfully logged in.
            """
            XCTAssertEqual(output, expectedOutput)
            verify(userInputReader)
                .readString(asking: .any)
                .called(0)
        }
    }
}
