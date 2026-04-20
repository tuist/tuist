import Foundation
import Mockable
import Testing
import TuistConstants
import TuistEnvironment
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

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) func authenticationToken_without_refresh_returns_nil_for_expired_token() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(-100), typ: "access")
            let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+60), typ: "refresh")
            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: refreshToken.token
            )
            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)

            // When
            let got = try await subject.authenticationToken(serverURL: serverURL, refreshIfNeeded: false)

            // Then
            #expect(got == nil)
            verify(refreshAuthTokenService)
                .refreshTokens(serverURL: .any, refreshToken: .any)
                .called(0)
        }
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) func authenticationToken_without_refresh_returns_valid_token() async throws {
        let date = Date()
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)
            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(+600), typ: "access")
            let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+3600), typ: "refresh")
            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: refreshToken.token
            )
            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)

            // When
            let got = try await subject.authenticationToken(serverURL: serverURL, refreshIfNeeded: false)

            // Then
            #expect(
                got == .user(
                    accessToken: try JWT.parse(accessToken.token),
                    refreshToken: try JWT.parse(refreshToken.token)
                )
            )
            verify(refreshAuthTokenService)
                .refreshTokens(serverURL: .any, refreshToken: .any)
                .called(0)
        }
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) func executeRefresh_sets_cache_expiration_based_on_access_token() async throws {
        let date = Date(timeIntervalSince1970: TimeInterval(Int(Date().timeIntervalSince1970)))
        try await Date.$now.withValue({ date }) {
            // Given
            let serverURL: URL = .test()
            let serverCredentialsStore = try #require(ServerCredentialsStore.mocked)

            let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(+600), typ: "access")
            let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+3600), typ: "refresh")
            let storeCredentials: ServerCredentials = .test(
                accessToken: accessToken.token,
                refreshToken: refreshToken.token
            )

            given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)

            // When
            let result = try await subject.executeRefresh(serverURL: serverURL, forceRefresh: false)

            // Then
            let expiresAt = try #require(result?.expiresAt)
            #expect(expiresAt == date.addingTimeInterval(+600))
        }
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) mutating func concurrent_refresh_without_locking_races_on_the_refresh_endpoint() async throws {
        // Regression test reproducing the iOS token refresh race. Before #10276
        // the iOS branch of `authenticationToken(serverURL:refreshIfNeeded:)`
        // passed `locking: false`, landing in `case (.expired, false, false)`
        // which calls `executeRefresh` directly — no cache coalescing, no
        // locking. In production that let multiple concurrent callers each
        // hit `/api/auth/refresh_token`; the server rotated the refresh token
        // on the winner and returned 401 to every loser, whose error path
        // wiped credentials and surfaced as "You need to be authenticated to
        // access this resource".
        let date = Date()
        let countingRefreshService = CountingRefreshAuthTokenService(
            tokens: try Self.makeTokens(date: date)
        )
        subject = ServerAuthenticationController(
            refreshAuthTokenService: countingRefreshService,
            cachedValueStore: CachedValueStore()
        )
        let serverCredentialsStore = MockServerCredentialsStoring()
        let serverURL: URL = .test()

        let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(-100), typ: "access")
        let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+3600), typ: "refresh")
        let storeCredentials: ServerCredentials = .test(
            accessToken: accessToken.token,
            refreshToken: refreshToken.token
        )

        given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)
        given(serverCredentialsStore).store(credentials: .any, serverURL: .value(serverURL)).willReturn()

        let subjectCopy = subject!
        try await ServerCredentialsStore.$current.withValue(serverCredentialsStore) {
            try await Date.$now.withValue({ date }) {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0 ..< 10 {
                        group.addTask {
                            try await subjectCopy.refreshToken(
                                serverURL: serverURL,
                                inBackground: false,
                                locking: false,
                                forceInProcessLock: false
                            )
                        }
                    }
                    try await group.waitForAll()
                }
            }
        }

        let callCount = await countingRefreshService.callCount
        #expect(callCount > 1, "Expected concurrent callers to race on the refresh endpoint, got \(callCount) calls")
    }

    @Test(
        .withMockedEnvironment(),
        .withMockedDependencies()
    ) mutating func concurrent_refresh_with_in_process_locking_coalesces_into_single_request() async throws {
        // Confirms the fix: routing expired tokens through
        // `inProcessLockedRefresh` serialises concurrent callers on the
        // `CachedValueStore` actor, so only a single refresh request reaches
        // the server regardless of how many API calls fire in parallel. This
        // is the path the iOS `#else` branch now uses after #10276.
        let date = Date()
        let countingRefreshService = CountingRefreshAuthTokenService(
            tokens: try Self.makeTokens(date: date)
        )
        subject = ServerAuthenticationController(
            refreshAuthTokenService: countingRefreshService,
            cachedValueStore: CachedValueStore()
        )
        let serverCredentialsStore = MockServerCredentialsStoring()
        let serverURL: URL = .test()

        let accessToken = try JWT.make(expiryDate: date.addingTimeInterval(-100), typ: "access")
        let refreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+3600), typ: "refresh")
        let storeCredentials: ServerCredentials = .test(
            accessToken: accessToken.token,
            refreshToken: refreshToken.token
        )

        given(serverCredentialsStore).read(serverURL: .value(serverURL)).willReturn(storeCredentials)
        given(serverCredentialsStore).store(credentials: .any, serverURL: .value(serverURL)).willReturn()

        let subjectCopy = subject!
        try await ServerCredentialsStore.$current.withValue(serverCredentialsStore) {
            try await Date.$now.withValue({ date }) {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0 ..< 10 {
                        group.addTask {
                            try await subjectCopy.refreshToken(
                                serverURL: serverURL,
                                inBackground: false,
                                locking: true,
                                forceInProcessLock: true
                            )
                        }
                    }
                    try await group.waitForAll()
                }
            }
        }

        let callCount = await countingRefreshService.callCount
        #expect(callCount == 1, "Expected coalesced callers to issue exactly one refresh, got \(callCount) calls")
    }

    private static func makeTokens(date: Date) throws -> ServerAuthenticationTokens {
        let newAccessToken = try JWT.make(expiryDate: date.addingTimeInterval(+600), typ: "access")
        let newRefreshToken = try JWT.make(expiryDate: date.addingTimeInterval(+7200), typ: "refresh")
        return ServerAuthenticationTokens(
            accessToken: newAccessToken.token,
            refreshToken: newRefreshToken.token
        )
    }
}

private actor CountingRefreshAuthTokenService: RefreshAuthTokenServicing {
    private let tokens: ServerAuthenticationTokens
    private(set) var callCount = 0

    init(tokens: ServerAuthenticationTokens) {
        self.tokens = tokens
    }

    func refreshTokens(
        serverURL _: URL,
        refreshToken _: String
    ) async throws -> ServerAuthenticationTokens {
        callCount += 1
        // Yield and sleep to give every concurrent caller a chance to enter
        // this method before any of them returns. Without the delay the
        // unlocked path can still serialise naturally if tasks happen to
        // resume before others get scheduled.
        await Task.yield()
        try await Task.sleep(nanoseconds: 100_000_000)
        return tokens
    }
}
