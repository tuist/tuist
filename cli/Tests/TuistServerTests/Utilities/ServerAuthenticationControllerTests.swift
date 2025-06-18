import Foundation
import Mockable
import Testing
import TuistSupport
import TuistTesting

@testable import TuistServer

struct ServerAuthenticationControllerTests {
    private var subject: ServerAuthenticationController!
    private var credentialsStore: MockServerCredentialsStoring!
    private var cachedValueStore: MockCachedValueStoring!
    private let refreshAuthTokenService: MockRefreshAuthTokenServicing!

    private let accessToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMiwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.qsxjD51lHHaQo6NWs-gUxVUhQfyWEe3v3-okM0NIV72vDY-fGgzq9JU2F8DQbdOD8POqWkseCbtO66m_4J9uFw"
    private let refreshToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMCwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.UGMOA4nysabRCO0px9ixCW3JTCA6OgYSeVA6X--Xkc8b-YA8ui2SeCL8gV9WvOYeLJA5pvzKUSulVfV1qM4LKg"

    init() throws {
        credentialsStore = .init()
        cachedValueStore = MockCachedValueStoring()
        refreshAuthTokenService = MockRefreshAuthTokenServicing()
        subject = .init(
            credentialsStore: credentialsStore,
            cachedValueStore: cachedValueStore,
            refreshAuthTokenService: refreshAuthTokenService
        )
    }

    @Test(.withMockedEnvironment()) func test_when_config_token_is_present_and_is_ci() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        let serverURL: URL = .test()
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
            "CI": "1",
        ]
        let authenticationToken: AuthenticationToken? = nil
        given(cachedValueStore).getValue(key: .value("token_\(serverURL.absoluteString)"), computeIfNeeded: .matching { closure in
            Task { try await closure() }
            return true
        }).willReturn(authenticationToken)

        // When
        let got = try await subject.authenticationToken(serverURL: serverURL)

        // Then
        #expect(
            got ==
                .project("project-token")
        )
    }

    @Test(.withMockedEnvironment()) func test_when_config_token_is_present_and_is_not_ci() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        let serverURL: URL = .test()
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
        ]
        given(credentialsStore)
            .read(serverURL: .any)
            .willReturn(nil)
        let authenticationToken: AuthenticationToken? = nil
        given(cachedValueStore).getValue(key: .value("token_\(serverURL.absoluteString)"), computeIfNeeded: .matching { closure in
            Task { try await closure() }
            return true
        }).willReturn(authenticationToken)

        // When
        let got = try await subject.authenticationToken(serverURL: .test())

        // Then
        #expect(got == nil)
    }

    @Test(.withMockedEnvironment()) func legacy_token_and_not_ci() async throws {
        // Given
<<<<<<< HEAD
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

=======
        let serverURL: URL = .test()
>>>>>>> 59540d87c (Move the refreshing logic to the ServerAuthenticationController)
        given(credentialsStore)
            .read(serverURL: .any)
            .willReturn(nil)
        let authenticationToken: AuthenticationToken? = .user(legacyToken: "legacy-token", accessToken: nil, refreshToken: nil)
        given(cachedValueStore).getValue(key: .value("token_\(serverURL.absoluteString)"), computeIfNeeded: .matching { closure in
            Task { try await closure() }
            return true
        }).willReturn(authenticationToken)
        given(credentialsStore).read(serverURL: .value(serverURL)).willReturn(.test(token: "legacy-token"))

        // When
        let got = try await subject.authenticationToken(serverURL: .test())

        // Then
        #expect(got == authenticationToken)
    }

    @Test(.withMockedEnvironment()) func non_expired_access_token_and_not_ci() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            given(credentialsStore)
                .read(serverURL: .any)
                .willReturn(nil)
            let authenticationToken: AuthenticationToken? = .user(
                legacyToken: "legacy-token",
                accessToken: nil,
                refreshToken: nil
            )

            given(cachedValueStore).getValue(
                key: .value("token_\(serverURL.absoluteString)"),
                computeIfNeeded: .matching { closure in
                    Task { try await closure() }
                    return true
                }
            ).willReturn(authenticationToken)

            let currentAccessToken = JWT.test(token: "access-token", expiryDate: date.addingTimeInterval(+60))
            let currentRefreshToken = JWT.test(token: "refresh-token", expiryDate: date.addingTimeInterval(+2000))
            given(credentialsStore).read(serverURL: .value(serverURL)).willReturn(.test(
                accessToken: try ServerAuthenticationController.encodeJWT(currentAccessToken),
                refreshToken: try ServerAuthenticationController.encodeJWT(currentRefreshToken)
            ))

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(got == authenticationToken)
        }
    }

    @Test(.withMockedEnvironment()) func expired_access_access_token_and_not_ci() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            given(credentialsStore)
                .read(serverURL: .any)
                .willReturn(nil)
            let authenticationToken: AuthenticationToken? = .user(
                legacyToken: "legacy-token",
                accessToken: nil,
                refreshToken: nil
            )

            given(cachedValueStore).getValue(
                key: .value("token_\(serverURL.absoluteString)"),
                computeIfNeeded: .matching { closure in
                    Task { try await closure() }
                    return true
                }
            ).willReturn(authenticationToken)

            let currentAccessToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "access-token",
                expiryDate: date.addingTimeInterval(-100)
            ))
            let currentRefreshToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refresh-token",
                expiryDate: date.addingTimeInterval(+2000)
            ))
            let refreshedAccessToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refreshed-access-token",
                expiryDate: date.addingTimeInterval(+10)
            ))
            let refreshedRefreshToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refreshed-refresh-token",
                expiryDate: date.addingTimeInterval(+2010)
            ))
            let refreshedServerCredentials = ServerCredentials.test(
                accessToken: refreshedAccessToken,
                refreshToken: refreshedRefreshToken
            )

            given(credentialsStore).read(serverURL: .value(serverURL)).willReturn(.test(
                accessToken: currentAccessToken,
                refreshToken: currentRefreshToken
            ))

            given(refreshAuthTokenService).refreshTokens(serverURL: .value(serverURL), refreshToken: .value(currentRefreshToken))
                .willReturn(.init(
                    accessToken: refreshedAccessToken,
                    refreshToken: refreshedRefreshToken
                ))
            given(credentialsStore).store(credentials: .value(refreshedServerCredentials), serverURL: .value(serverURL))
                .willReturn()

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(got == authenticationToken)
        }
    }

    @Test(.withMockedEnvironment()) func close_to_expired_access_token_and_not_ci() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            given(credentialsStore)
                .read(serverURL: .any)
                .willReturn(nil)
            let authenticationToken: AuthenticationToken? = .user(
                legacyToken: "legacy-token",
                accessToken: nil,
                refreshToken: nil
            )

            given(cachedValueStore).getValue(
                key: .value("token_\(serverURL.absoluteString)"),
                computeIfNeeded: .matching { closure in
                    Task { try await closure() }
                    return true
                }
            ).willReturn(authenticationToken)

            let currentAccessToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "access-token",
                expiryDate: date.addingTimeInterval(5)
            ))
            let currentRefreshToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refresh-token",
                expiryDate: date.addingTimeInterval(+2000)
            ))
            let refreshedAccessToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refreshed-access-token",
                expiryDate: date.addingTimeInterval(+10)
            ))
            let refreshedRefreshToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refreshed-refresh-token",
                expiryDate: date.addingTimeInterval(+2010)
            ))
            let refreshedServerCredentials = ServerCredentials.test(
                accessToken: refreshedAccessToken,
                refreshToken: refreshedRefreshToken
            )

            given(credentialsStore).read(serverURL: .value(serverURL)).willReturn(.test(
                accessToken: currentAccessToken,
                refreshToken: currentRefreshToken
            ))

            given(refreshAuthTokenService).refreshTokens(serverURL: .value(serverURL), refreshToken: .value(currentRefreshToken))
                .willReturn(.init(
                    accessToken: refreshedAccessToken,
                    refreshToken: refreshedRefreshToken
                ))
            given(credentialsStore).store(credentials: .value(refreshedServerCredentials), serverURL: .value(serverURL))
                .willReturn()

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(got == authenticationToken)
        }
    }

    @Test(.withMockedEnvironment()) func non_expired_access_token_when_forced_and_not_ci() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            given(credentialsStore)
                .read(serverURL: .any)
                .willReturn(nil)
            let authenticationToken: AuthenticationToken? = .user(
                legacyToken: "legacy-token",
                accessToken: nil,
                refreshToken: nil
            )

            given(cachedValueStore).getValue(
                key: .value("token_\(serverURL.absoluteString)"),
                computeIfNeeded: .matching { closure in
                    Task { try await closure() }
                    return true
                }
            ).willReturn(authenticationToken)

            let currentAccessToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "access-token",
                expiryDate: date.addingTimeInterval(60)
            ))
            let currentRefreshToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refresh-token",
                expiryDate: date.addingTimeInterval(+2000)
            ))
            let refreshedAccessToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refreshed-access-token",
                expiryDate: date.addingTimeInterval(+10)
            ))
            let refreshedRefreshToken = try ServerAuthenticationController.encodeJWT(JWT.test(
                token: "refreshed-refresh-token",
                expiryDate: date.addingTimeInterval(+2010)
            ))
            let refreshedServerCredentials = ServerCredentials.test(
                accessToken: refreshedAccessToken,
                refreshToken: refreshedRefreshToken
            )

            given(credentialsStore).read(serverURL: .value(serverURL)).willReturn(.test(
                accessToken: currentAccessToken,
                refreshToken: currentRefreshToken
            ))

            given(refreshAuthTokenService).refreshTokens(serverURL: .value(serverURL), refreshToken: .value(currentRefreshToken))
                .willReturn(.init(
                    accessToken: refreshedAccessToken,
                    refreshToken: refreshedRefreshToken
                ))
            given(credentialsStore).store(credentials: .value(refreshedServerCredentials), serverURL: .value(serverURL))
                .willReturn()

            // When
            let got = try await subject.authenticationToken(serverURL: .test(), forceRefresh: true)

            // Then
            #expect(got == authenticationToken)
        }
    }
}
