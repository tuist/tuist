import Foundation
import Mockable
import Testing
import TuistSupport
import TuistTesting

@testable import TuistServer

struct ServerAuthenticationControllerTests {
    struct TestError: Error, Equatable {}

    private var subject: ServerAuthenticationController!
    private let refreshAuthTokenService: MockRefreshAuthTokenServicing!
    private let cachedValueStore: MockCachedValueStoring

    private let accessToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMiwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.qsxjD51lHHaQo6NWs-gUxVUhQfyWEe3v3-okM0NIV72vDY-fGgzq9JU2F8DQbdOD8POqWkseCbtO66m_4J9uFw"
    private let refreshToken =
        "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJ0dWlzdF9jbG91ZCIsImV4cCI6MTcyMDQyOTgxMCwiaWF0IjoxNzIwNDI5NzUyLCJpc3MiOiJ0dWlzdF9jbG91ZCIsImp0aSI6IjlmZGEwYmRmLTE0MjMtNDhmNi1iNWRmLWM2MDVjMGMwMzBiMiIsIm5iZiI6MTcyMDQyOTc1MSwicmVzb3VyY2UiOiJ1c2VyIiwic3ViIjoiMSIsInR5cCI6ImFjY2VzcyJ9.UGMOA4nysabRCO0px9ixCW3JTCA6OgYSeVA6X--Xkc8b-YA8ui2SeCL8gV9WvOYeLJA5pvzKUSulVfV1qM4LKg"

    init() throws {
        cachedValueStore = MockCachedValueStoring()
        refreshAuthTokenService = MockRefreshAuthTokenServicing()
        subject = ServerAuthenticationController(
            refreshAuthTokenService: refreshAuthTokenService,
            cachedValueStore: cachedValueStore
        )
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies()) func when_config_token_is_present_and_is_ci() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        let serverURL: URL = .test()
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
            "CI": "1",
        ]
        let authenticationToken: AuthenticationToken? = nil
        let cachedValueStore = try #require(CachedValueStore.mocked)
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

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) func when_config_token_is_present_and_is_not_ci() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            Constants.EnvironmentVariables.token: "project-token",
        ]
        let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
        given(serverCredentialsStore)
            .read(serverURL: .any)
            .willReturn(nil)

        // When
        let got = try await subject.authenticationToken(serverURL: .test())

        // Then
        #expect(got == .project("project-token"))
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies()) func non_expired_access_token_and_is_ci() async throws {
        let date = Date()
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CI": "1",
        ]
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "access")
            let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "refresh")

            let authenticationToken: AuthenticationToken? = .user(
                accessToken: try JWT.parse(accessToken.token),
                refreshToken: try JWT.parse(refreshToken.token)
            )

            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: refreshToken.token
            )

            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)
            given(cachedValueStore).getValue(
                key: .value("token_\(serverURL.absoluteString)"),
                computeIfNeeded: .matching { closure in
                    Task { try await closure() }
                    return true
                }
            ).willReturn(authenticationToken)

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(got == authenticationToken)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies()) func non_expired_access_token_and_not_ci() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "access")
            let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "refresh")

            let authenticationToken: AuthenticationToken? = .user(
                accessToken: try JWT.parse(accessToken.token),
                refreshToken: try JWT.parse(refreshToken.token)
            )

            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: refreshToken.token
            )

            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)
            given(cachedValueStore).getValue(
                key: .value("token_\(serverURL.absoluteString)"),
                computeIfNeeded: .matching { closure in
                    Task { try await closure() }
                    return true
                }
            ).willReturn(authenticationToken)

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(got == authenticationToken)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies()) func expired_access_token_and_not_ci_and_locking() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(-100), typ: "access")
            let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "refresh")

            let authenticationToken: AuthenticationToken? = .user(
                accessToken: try JWT.parse(accessToken.token),
                refreshToken: try JWT.parse(refreshToken.token)
            )

            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: refreshToken.token
            )

            given(cachedValueStore).getValue(key: .any, computeIfNeeded: .any).willReturn(authenticationToken)

            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)

            // When/Then
            try await subject.refreshToken(
                serverURL: serverURL,
                inBackground: false,
                locking: true,
                forceInProcessLock: true
            )
        }
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies()) func non_expired_account_token() async throws {
        let date = Date()
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CI": "1",
        ]
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "access", type: "account")

            let authenticationToken: AuthenticationToken? = .account(try JWT.parse(accessToken.token))

            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: ""
            )

            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)
            given(cachedValueStore).getValue(
                key: .value("token_\(serverURL.absoluteString)"),
                computeIfNeeded: .matching { closure in
                    Task { try await closure() }
                    return true
                }
            ).willReturn(authenticationToken)

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(got == authenticationToken)
        }
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies()) func expired_account_token_returns_expired() async throws {
        let date = Date()
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [
            "CI": "1",
        ]
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(-100), typ: "access", type: "account")

            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: ""
            )

            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)
            given(cachedValueStore).getValue(key: .any, computeIfNeeded: .any).willReturn(nil as AuthenticationToken?)

            // When
            let got = try await subject.authenticationToken(serverURL: .test())

            // Then
            #expect(got == nil)
        }
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) mutating func expired_access_token_and_not_ci_and_locking_and_failing_refresh() async throws {
        let date = Date()
        subject = ServerAuthenticationController(
            refreshAuthTokenService: refreshAuthTokenService,
            cachedValueStore: CachedValueStore()
        )
        let serverCredentialsStore = MockServerCredentialsStoring()
        let serverURL: URL = .test()
        let error = RefreshAuthTokenServiceError.unauthorized("Invalid token")
        given(refreshAuthTokenService).refreshTokens(serverURL: .value(serverURL), refreshToken: .any).willThrow(error)
        given(serverCredentialsStore).delete(serverURL: .value(serverURL)).willReturn()

        try await ServerCredentialsStore.$current.withValue(serverCredentialsStore) {
            try await Date.$now.withValue({ date }) {
                // Given
                let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
                let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(-100), typ: "access")
                let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "refresh")

                let storeCredentials: ServerCredentials = .test(
                    accessToken: accessToken.token,
                    refreshToken: refreshToken.token
                )

                given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)

                // When/Then
                await #expect(throws: error, performing: {
                    try await subject.refreshToken(
                        serverURL: serverURL,
                        inBackground: false,
                        locking: true,
                        forceInProcessLock: true
                    )
                })
            }
        }
    }
}
