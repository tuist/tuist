import Foundation
import Mockable
import Testing
import TuistSupport
import TuistTesting

@testable import TuistServer

struct ServerAuthenticationControllerTests {
    private var subject: ServerAuthenticationController!
    private var credentialsStore: MockServerCredentialsStoring!

    private let accessToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMiwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.qsxjD51lHHaQo6NWs-gUxVUhQfyWEe3v3-okM0NIV72vDY-fGgzq9JU2F8DQbdOD8POqWkseCbtO66m_4J9uFw"
    private let refreshToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMCwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.UGMOA4nysabRCO0px9ixCW3JTCA6OgYSeVA6X--Xkc8b-YA8ui2SeCL8gV9WvOYeLJA5pvzKUSulVfV1qM4LKg"

    init() throws {
        credentialsStore = .init()
        subject = .init(
            credentialsStore: credentialsStore
        )
    }

    @Test(.withMockedEnvironment()) func test_when_config_token_is_present_and_is_ci() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
            "CI": "1",
        ]

        // When
        let got = try await subject.authenticationToken(serverURL: .test())

        // Then
        #expect(
            got ==
                .project("project-token")
        )
    }

    @Test(.withMockedEnvironment()) func test_when_config_token_is_present_and_is_not_ci() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
        ]
        given(credentialsStore)
            .read(serverURL: .any)
            .willReturn(nil)

        // When
        let got = try await subject.authenticationToken(serverURL: .test())

        // Then
        #expect(got == nil)
    }

    @Test(.withMockedEnvironment()) func test_when_config_token_is_present_and_is_not_ci_and_tuist_dev_credentials_are_missing()
        async throws
    {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
        ]
        let credentials = ServerCredentials.test(token: "access-token")

        given(credentialsStore)
            .read(serverURL: .value(URL(string: "https://tuist.dev")!))
            .willReturn(nil)
        given(credentialsStore)
            .read(serverURL: .value(URL(string: "https://tuist.dev")!))
            .willReturn(credentials)

        // When
        let got = try await subject.authenticationToken(
            serverURL: URL(string: "https://tuist.dev")!
        )

        // Then
        #expect(got?.value == credentials.token)
    }

    @Test(.withMockedEnvironment()) func test_when_config_token_is_present_and_is_not_ci_and_tuist_dev_credentials_are_present()
        async throws
    {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
        ]
        let credentials = ServerCredentials.test(token: "access-token")
        given(credentialsStore)
            .read(serverURL: .value(URL(string: "https://tuist.dev")!))
            .willReturn(credentials)

        // When
        let got = try await subject.authenticationToken(
            serverURL: URL(string: "https://tuist.dev")!
        )

        // Then
        #expect(got?.value == credentials.token)
    }

    @Test(.withMockedEnvironment()) func test_when_deprecated_config_token_is_present_and_is_ci() async throws {
        try await withMockedDependencies {
            // Given
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = [
                Constants.EnvironmentVariables.deprecatedToken: "project-token",
                "CI": "1",
            ]

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(
                got ==
                    .project("project-token")
            )
            try TuistTest.expectLogs(
                "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
            )
        }
    }

    @Test(.withMockedEnvironment()) func test_when_deprecated_and_current_config_tokens_are_present_and_is_ci() async throws {
        try await withMockedDependencies {
            // Given
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = [
                Constants.EnvironmentVariables.deprecatedToken: "deprecated-project-token",
                Constants.EnvironmentVariables.token: "project-token",
                "CI": "1",
            ]

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(
                got ==
                    .project("project-token")
            )
            TuistTest.doesntExpectLogs(
                "Use `TUIST_CONFIG_TOKEN` environment variable instead of `TUIST_CONFIG_CLOUD_TOKEN` to authenticate on the CI"
            )
        }
    }

    @Test(.withMockedEnvironment()) func test_when_credentials_store_returns_legacy_token() async throws {
        try await withMockedDependencies {
            // Given
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = [:]

            given(credentialsStore)
                .read(serverURL: .any)
                .willReturn(
                    ServerCredentials(token: "legacy-token", accessToken: nil, refreshToken: nil)
                )

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(
                got ==
                    .user(legacyToken: "legacy-token", accessToken: nil, refreshToken: nil)
            )
            TuistTest.expectLogs(
                "You are using a deprecated user token. Please, reauthenticate by running 'tuist auth login'."
            )
        }
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedLogger()
    ) func test_when_credentials_store_returns_legacy_token_and_jwt_tokens() async throws {
        try await withMockedDependencies {
            // Given
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = [:]

            given(credentialsStore)
                .read(serverURL: .any)
                .willReturn(
                    .test(
                        token: "legacy-token",
                        accessToken: accessToken,
                        refreshToken: refreshToken
                    )
                )

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(
                got ==
                    .user(
                        legacyToken: nil,
                        accessToken: .test(
                            token: accessToken,
                            expiryDate: Date(timeIntervalSince1970: 1_720_429_812)
                        ),
                        refreshToken: .test(
                            token: refreshToken,
                            expiryDate: Date(timeIntervalSince1970: 1_720_429_810)
                        )
                    )
            )
            TuistTest.doesntExpectLogs(
                "You are using a deprecated user token. Please, reauthenticate by running 'tuist auth login'."
            )
        }
    }

    @Test(.withMockedEnvironment()) func test_when_credentials_store_returns_jwt_tokens() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]

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
        let got = try await subject.authenticationToken(serverURL: .test())

        // Then
        #expect(
            got ==
                .user(
                    legacyToken: nil,
                    accessToken: .test(
                        token: accessToken,
                        expiryDate: Date(timeIntervalSince1970: 1_720_429_812)
                    ),
                    refreshToken: .test(
                        token: refreshToken,
                        expiryDate: Date(timeIntervalSince1970: 1_720_429_810)
                    )
                )
        )
    }
}
