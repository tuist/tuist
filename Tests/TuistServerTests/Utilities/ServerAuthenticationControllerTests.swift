import Foundation
import MockableTest
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistServer

final class ServerAuthenticationControllerTests: TuistUnitTestCase {
    private var subject: ServerAuthenticationController!
    private var credentialsStore: MockServerCredentialsStoring!
    private var ciChecker: MockCIChecking!

    private let accessToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMiwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.qsxjD51lHHaQo6NWs-gUxVUhQfyWEe3v3-okM0NIV72vDY-fGgzq9JU2F8DQbdOD8POqWkseCbtO66m_4J9uFw"
    private let refreshToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMCwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.UGMOA4nysabRCO0px9ixCW3JTCA6OgYSeVA6X--Xkc8b-YA8ui2SeCL8gV9WvOYeLJA5pvzKUSulVfV1qM4LKg"

    override func setUp() {
        super.setUp()

        credentialsStore = .init()
        ciChecker = .init()
        subject = .init(
            credentialsStore: credentialsStore,
            ciChecker: ciChecker,
            environment: environment
        )
    }

    override func tearDown() {
        credentialsStore = nil
        ciChecker = nil
        subject = nil
        super.tearDown()
    }

    func test_when_config_token_is_present_and_is_ci() throws {
        // Given
        environment.tuistVariables[
            Constants.EnvironmentVariables.token
        ] = "project-token"
        given(ciChecker)
            .isCI()
            .willReturn(true)

        // When
        let got = try subject.authenticationToken(serverURL: .test())

        // Then
        XCTAssertEqual(
            got,
            .project("project-token")
        )
    }

    func test_when_config_token_is_present_and_is_not_ci() throws {
        // Given
        environment.tuistVariables[
            Constants.EnvironmentVariables.token
        ] = "project-token"
        given(ciChecker)
            .isCI()
            .willReturn(false)
        given(credentialsStore)
            .read(serverURL: .any)
            .willReturn(nil)

        // When
        let got = try subject.authenticationToken(serverURL: .test())

        // Then
        XCTAssertNil(got)
    }

    func test_when_deprecated_config_token_is_present_and_is_ci() throws {
        // Given
        environment.tuistVariables[
            Constants.EnvironmentVariables.deprecatedToken
        ] = "project-token"
        given(ciChecker)
            .isCI()
            .willReturn(true)

        // When
        let got = try subject.authenticationToken(serverURL: .test())

        // Then
        XCTAssertEqual(
            got,
            .project("project-token")
        )
        XCTAssertStandardOutput(
            pattern: "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
        )
    }

    func test_when_deprecated_and_current_config_tokens_are_present_and_is_ci() throws {
        // Given
        environment.tuistVariables[
            Constants.EnvironmentVariables.deprecatedToken
        ] = "deprecated-project-token"
        environment.tuistVariables[
            Constants.EnvironmentVariables.token
        ] = "project-token"
        given(ciChecker)
            .isCI()
            .willReturn(true)

        // When
        let got = try subject.authenticationToken(serverURL: .test())

        // Then
        XCTAssertEqual(
            got,
            .project("project-token")
        )
        XCTAssertPrinterOutputNotContains(
            "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
        )
    }

    func test_when_credentials_store_returns_legacy_token() throws {
        // Given
        given(ciChecker)
            .isCI()
            .willReturn(false)

        given(credentialsStore)
            .read(serverURL: .any)
            .willReturn(ServerCredentials(token: "legacy-token", accessToken: nil, refreshToken: nil))

        // When
        let got = try subject.authenticationToken(serverURL: .test())

        // Then
        XCTAssertEqual(
            got,
            .user(legacyToken: "legacy-token", accessToken: nil, refreshToken: nil)
        )
        XCTAssertStandardOutput(pattern: "You are using a deprecated user token. Please, reauthenticate by running `tuist auth`.")
    }

    func test_when_credentials_store_returns_legacy_token_and_jwt_tokens() throws {
        // Given
        given(ciChecker)
            .isCI()
            .willReturn(false)

        given(credentialsStore)
            .read(serverURL: .any)
            .willReturn(ServerCredentials(token: "legacy-token", accessToken: accessToken, refreshToken: refreshToken))

        // When
        let got = try subject.authenticationToken(serverURL: .test())

        // Then
        // Then
        XCTAssertEqual(
            got,
            .user(
                legacyToken: nil,
                accessToken: JWT(
                    token: accessToken,
                    expiryDate: Date(timeIntervalSince1970: 1_720_429_812)
                ),
                refreshToken: JWT(
                    token: refreshToken,
                    expiryDate: Date(timeIntervalSince1970: 1_720_429_810)
                )
            )
        )
        XCTAssertPrinterOutputNotContains(
            "You are using a deprecated user token. Please, reauthenticate by running `tuist auth`."
        )
    }

    func test_when_credentials_store_returns_jwt_tokens() throws {
        // Given
        given(ciChecker)
            .isCI()
            .willReturn(false)

        given(credentialsStore)
            .read(serverURL: .any)
            .willReturn(
                ServerCredentials(
                    token: nil,
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
            )

        // When
        let got = try subject.authenticationToken(serverURL: .test())

        // Then
        XCTAssertEqual(
            got,
            .user(
                legacyToken: nil,
                accessToken: JWT(
                    token: accessToken,
                    expiryDate: Date(timeIntervalSince1970: 1_720_429_812)
                ),
                refreshToken: JWT(
                    token: refreshToken,
                    expiryDate: Date(timeIntervalSince1970: 1_720_429_810)
                )
            )
        )
    }
}
