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
        let serverURL: URL = .test()
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
                accessToken: try currentAccessToken.encode(),
                refreshToken: try currentRefreshToken.encode()
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

            let currentAccessToken = try JWT.test(
                token: "access-token",
                expiryDate: date.addingTimeInterval(-100)
            ).encode()
            let currentRefreshToken = try JWT.test(
                token: "refresh-token",
                expiryDate: date.addingTimeInterval(+2000)
            ).encode()
            let refreshedAccessToken = try JWT.test(
                token: "refreshed-access-token",
                expiryDate: date.addingTimeInterval(+10)
            ).encode()
            let refreshedRefreshToken = try JWT.test(
                token: "refreshed-refresh-token",
                expiryDate: date.addingTimeInterval(+2010)
            ).encode()
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

            let currentAccessToken = try JWT.test(
                token: "access-token",
                expiryDate: date.addingTimeInterval(5)
            ).encode()
            let currentRefreshToken = try JWT.test(
                token: "refresh-token",
                expiryDate: date.addingTimeInterval(+2000)
            ).encode()
            let refreshedAccessToken = try JWT.test(
                token: "refreshed-access-token",
                expiryDate: date.addingTimeInterval(+10)
            ).encode()
            let refreshedRefreshToken = try JWT.test(
                token: "refreshed-refresh-token",
                expiryDate: date.addingTimeInterval(+2010)
            ).encode()
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

            let currentAccessToken = try JWT.test(
                token: "access-token",
                expiryDate: date.addingTimeInterval(60)
            ).encode()
            let currentRefreshToken = try JWT.test(
                token: "refresh-token",
                expiryDate: date.addingTimeInterval(+2000)
            ).encode()
            let refreshedAccessToken = try JWT.test(
                token: "refreshed-access-token",
                expiryDate: date.addingTimeInterval(+10)
            ).encode()
            let refreshedRefreshToken = try JWT.test(
                token: "refreshed-refresh-token",
                expiryDate: date.addingTimeInterval(+2010)
            ).encode()
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
}
