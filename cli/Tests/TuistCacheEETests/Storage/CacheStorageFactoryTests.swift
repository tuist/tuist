import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCAS
import TuistConfig
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer
import TuistSupport
import XcodeGraph

@testable import TuistCacheEE
@testable import TuistSupport
@testable import TuistTesting

struct CacheStorageFactoryTests {
    private var cacheDirectoriesProvider: CacheDirectoriesProvider
    private var cacheURLStore: MockCacheURLStoring
    private var serverAuthenticationController: MockServerAuthenticationControlling
    private var subject: CacheStorageFactory
    private var serverEnvironmentService: MockServerEnvironmentServicing

    init() {
        cacheDirectoriesProvider = CacheDirectoriesProvider()
        cacheURLStore = MockCacheURLStoring()
        serverAuthenticationController = MockServerAuthenticationControlling()
        serverEnvironmentService = MockServerEnvironmentServicing()
        subject = CacheStorageFactory(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            serverAuthenticationController: serverAuthenticationController,
            serverEnvironmentService: serverEnvironmentService,
            cacheURLStore: cacheURLStore
        )
    }

    @Test
    func when_no_server_configuration() async throws {
        // Given
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)

        // When
        let got = try await subject.cacheStorage(config: .test(fullHandle: nil))

        // Then
        #expect((got as? CacheStorage)?.remoteStorage == nil)
    }

    @Test
    func when_serverURL_configuration_and_valid_tokens() async throws {
        try await withMockedEnvironment {
            // Given
            given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
            let token: AuthenticationToken = .user(
                accessToken: .test(token: "access-token"),
                refreshToken: .test(token: "refresh-token")
            )
            given(serverAuthenticationController).authenticationToken(
                serverURL: .value(Constants.URLs.production),
                refreshIfNeeded: .any
            ).willReturn(token)
            given(cacheURLStore)
                .getCacheURL(for: .value(Constants.URLs.production), accountHandle: .value("tuist"))
                .willReturn(URL(string: "https://cache.example.com")!)

            // When
            let got = try await subject.cacheStorage(
                config: .test(
                    fullHandle: "tuist/tuist",
                    url: Constants.URLs.production
                )
            )

            // Then
            #expect((got as? CacheStorage)?.remoteStorage != nil)
        }
    }

    @Test
    func when_serverURL_configuration_and_valid_tokens_legacy() async throws {
        try await withMockedEnvironment {
            Environment.mocked?.variables["TUIST_LEGACY_MODULE_CACHE"] = "1"
            // Given
            given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
            let token: AuthenticationToken = .user(
                accessToken: .test(token: "access-token"),
                refreshToken: .test(token: "refresh-token")
            )
            given(serverAuthenticationController).authenticationToken(
                serverURL: .value(Constants.URLs.production),
                refreshIfNeeded: .any
            ).willReturn(token)

            // When
            let got = try await subject.cacheStorage(
                config: .test(
                    fullHandle: "tuist/tuist",
                    url: Constants.URLs.production
                )
            )

            // Then
            #expect((got as? CacheStorage)?.remoteStorage != nil)
        }
    }

    @Test
    func when_storages_local_only() async throws {
        // Given: no server mocks needed — serverURL should never be resolved

        // When
        let got = try await subject.cacheStorage(
            config: .test(
                project: .generated(.test(cacheOptions: .test(storages: [.local]))),
                fullHandle: "tuist/tuist",
                url: Constants.URLs.production
            )
        )

        // Then
        #expect((got as? CacheStorage)?.remoteStorage == nil)
    }

    @Test
    func when_serverURL_configuration_and_absent_token() async throws {
        // Given
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(Constants.URLs.production),
            refreshIfNeeded: .any
        ).willReturn(nil)

        // When/Then
        await #expect(throws: CacheStorageFactoryError.tokenNotFound) {
            try await subject.cacheStorage(
                config: .test(
                    fullHandle: "tuist/tuist",
                    url: Constants.URLs.production
                )
            )
        }
    }

    @Test
    func refreshes_expired_tokens_when_optional_authentication_is_enabled() async throws {
        // Regression: with `optionalAuthentication`, the factory used to pass
        // `refreshIfNeeded: false`, so an expired access token would silently
        // skip the remote cache even when the user had a valid refresh token in
        // their credentials. Refresh must be attempted on every call so
        // authenticated sessions stay live across the access token's TTL.
        try await withMockedEnvironment {
            // Given
            given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
            let token: AuthenticationToken = .user(
                accessToken: .test(token: "refreshed-access-token"),
                refreshToken: .test(token: "refresh-token")
            )
            given(serverAuthenticationController).authenticationToken(
                serverURL: .value(Constants.URLs.production),
                refreshIfNeeded: .value(true)
            ).willReturn(token)
            given(cacheURLStore)
                .getCacheURL(for: .value(Constants.URLs.production), accountHandle: .value("tuist"))
                .willReturn(URL(string: "https://cache.example.com")!)

            // When
            let got = try await subject.cacheStorage(
                config: .test(
                    project: .generated(.test(generationOptions: .test(optionalAuthentication: true))),
                    fullHandle: "tuist/tuist",
                    url: Constants.URLs.production
                )
            )

            // Then
            #expect((got as? CacheStorage)?.remoteStorage != nil)
            verify(serverAuthenticationController)
                .authenticationToken(
                    serverURL: .value(Constants.URLs.production),
                    refreshIfNeeded: .value(true)
                )
                .called(1)
        }
    }

    @Test
    func swallows_refresh_errors_when_optional_authentication_is_enabled() async throws {
        // When refresh itself throws (network failure, refresh token revoked,
        // credentials wiped after a 401), `optionalAuthentication` should fall
        // through to the warning branch instead of crashing the generate
        // command. This is the safety valve that motivated the original
        // skip-refresh shortcut, but without losing the refresh.
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(Constants.URLs.production),
            refreshIfNeeded: .value(true)
        ).willThrow(RefreshAuthTokenServiceError.unauthorized("Invalid token"))

        // When
        let got = try await subject.cacheStorage(
            config: .test(
                project: .generated(.test(generationOptions: .test(optionalAuthentication: true))),
                fullHandle: "tuist/tuist",
                url: Constants.URLs.production
            )
        )

        // Then
        #expect((got as? CacheStorage)?.remoteStorage == nil)
    }

    @Test
    func propagates_refresh_errors_when_optional_authentication_is_disabled() async throws {
        // Without `optionalAuthentication`, a refresh failure must bubble up so
        // the user gets an actionable error instead of an inexplicably missing
        // remote cache.
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
        let error = RefreshAuthTokenServiceError.unauthorized("Invalid token")
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(Constants.URLs.production),
            refreshIfNeeded: .value(true)
        ).willThrow(error)

        // When/Then
        await #expect(throws: error) {
            try await subject.cacheStorage(
                config: .test(
                    fullHandle: "tuist/tuist",
                    url: Constants.URLs.production
                )
            )
        }
    }
}
