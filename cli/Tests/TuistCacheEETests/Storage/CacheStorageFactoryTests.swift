import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCAS
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
                serverURL: .value(Constants.URLs.production)
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
                serverURL: .value(Constants.URLs.production)
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
    func when_serverURL_configuration_and_absent_token() async throws {
        // Given
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(Constants.URLs.production)
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
}
