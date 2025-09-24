import Foundation
import Mockable
import Path
import TuistCache
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class CacheStorageFactoryTests: TuistUnitTestCase {
    private var cacheDirectoriesProvider: CacheDirectoriesProvider!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var subject: CacheStorageFactory!
    private var serverEnvironmentService: MockServerEnvironmentServicing!

    override func setUp() async throws {
        try await super.setUp()
        cacheDirectoriesProvider = CacheDirectoriesProvider()
        serverAuthenticationController = MockServerAuthenticationControlling()
        serverEnvironmentService = MockServerEnvironmentServicing()
        subject = CacheStorageFactory(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            serverAuthenticationController: serverAuthenticationController,
            serverEnvironmentService: serverEnvironmentService,
            environmentVariables: [:]
        )
    }

    override func tearDown() {
        cacheDirectoriesProvider = nil
        serverAuthenticationController = nil
        serverEnvironmentService = nil
        subject = nil
        super.tearDown()
    }

    func test_when_no_server_configuration() async throws {
        // Given
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)

        // When
        let got = try await subject.cacheStorage(config: .test(fullHandle: nil))

        // Then
        XCTAssertNil((got as? CacheStorage)?.remoteStorage)
    }

    func test_when_serverURL_configuration_and_valid_tokens() async throws {
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
        XCTAssertNotNil((got as? CacheStorage)?.remoteStorage)
    }

    func test_when_serverURL_configuration_and_absent_token() async throws {
        // Given
        given(serverEnvironmentService).url(configServerURL: .any).willReturn(Constants.URLs.production)
        given(serverAuthenticationController).authenticationToken(
            serverURL: .value(Constants.URLs.production)
        ).willReturn(nil)

        // When
        await XCTAssertThrowsSpecific(
            try await subject.cacheStorage(
                config: .test(
                    fullHandle: "tuist/tuist",
                    url: Constants.URLs.production
                )
            ),
            CacheStorageFactoryError.tokenNotFound
        )
    }
}

final class CacheStorageTests: TuistUnitTestCase {
    private var localStorage: MockCacheStoring!
    private var remoteStorage: MockCacheStoring!
    private var subject: CacheStorage!

    override func setUp() {
        super.setUp()

        localStorage = MockCacheStoring()
        remoteStorage = MockCacheStoring()
        subject = CacheStorage(
            localStorage: localStorage,
            remoteStorage: remoteStorage
        )
    }

    override func tearDown() {
        localStorage = nil
        remoteStorage = nil
        subject = nil
        super.tearDown()
    }

    func test_fetch_when_item_present_in_the_local_cache() async throws {
        // Given
        let cacheStorableItem = CacheStorableItem(name: "targetName", hash: "1234")
        let cacheItem: CacheItem = .test(name: "targetName", hash: "1234")
        let path: AbsolutePath = "/Absolute/Path"
        given(localStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            cacheItem: path,
        ])
        given(remoteStorage).fetch(.value(Set([])), cacheCategory: .value(.binaries)).willReturn(
            [:]
        )

        // When
        let result = try await subject.fetch([cacheStorableItem], cacheCategory: .binaries)

        // Then
        XCTAssertEqual(result[cacheItem], "/Absolute/Path")
    }

    func test_fetch_when_in_second_cache_checks_both_and_returns_path() async throws {
        // Given
        let cacheStorableItem = CacheStorableItem(name: "targetName", hash: "1234")
        let cacheItem: CacheItem = .test(name: "targetName", hash: "1234")
        let path: AbsolutePath = "/Absolute/Path"
        given(localStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([:])
        given(remoteStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([
            cacheItem: path,
        ])

        // When
        let result = try await subject.fetch([cacheStorableItem], cacheCategory: .binaries)

        // Then
        XCTAssertEqual(result[cacheItem], "/Absolute/Path")
    }

    func test_fetch_when_item_absent_in_both_caches() async throws {
        // Given
        let cacheStorableItem = CacheStorableItem(name: "targetName", hash: "1234")
        let cacheItem: CacheItem = .test(name: "targetName", hash: "1234")
        given(localStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([:])
        given(remoteStorage).fetch(
            .value(
                Set([
                    cacheStorableItem,
                ])
            ), cacheCategory: .value(.binaries)
        ).willReturn([:])

        // When
        let result = try await subject.fetch([cacheStorableItem], cacheCategory: .binaries)

        // Then
        XCTAssertEqual(result[cacheItem], nil)
    }
}
