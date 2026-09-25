import Foundation
import Mockable
import Testing
import TuistAlert
import TuistCache
import TuistCAS
import TuistConfig
import TuistCore
import TuistServer
import TuistSupport
@testable import TuistKit
@testable import TuistTesting

struct CacheStorageFactoryingLocalFallbackTests {
    private let cacheStorageFactory = MockCacheStorageFactorying()
    private let localCacheStorage = MockCacheStoring()

    init() {
        given(cacheStorageFactory)
            .cacheLocalStorage()
            .willReturn(localCacheStorage)
    }

    @Test func uses_the_local_cache_and_warns_while_the_remote_cache_is_being_prepared() async throws {
        // Given
        let alertController = AlertController()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willThrow(CacheURLStoreError.endpointBeingPrepared)

        // When
        _ = try await AlertController.$current.withValue(alertController) {
            try await cacheStorageFactory.cacheStorageFallingBackToLocal(config: .test())
        }

        // Then
        verify(cacheStorageFactory)
            .cacheLocalStorage()
            .called(1)
        #expect(
            alertController.warnings().map(\.message).map { $0.plain() } == [
                "The remote cache is still being prepared.",
            ]
        )
    }

    @Test func warns_once_when_the_remote_cache_is_asked_for_more_than_once() async throws {
        // Given
        let alertController = AlertController()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willThrow(CacheURLStoreError.endpointBeingPrepared)

        // When
        try await AlertController.$current.withValue(alertController) {
            _ = try await cacheStorageFactory.cacheStorageFallingBackToLocal(config: .test())
            _ = try await cacheStorageFactory.cacheStorageFallingBackToLocal(config: .test())
        }

        // Then
        #expect(alertController.warnings().count == 1)
    }

    @Test func uses_the_local_cache_when_no_remote_cache_endpoint_is_available() async throws {
        // Given
        let alertController = AlertController()
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willThrow(CacheURLStoreError.noEndpointsAvailable)

        // When
        _ = try await AlertController.$current.withValue(alertController) {
            try await cacheStorageFactory.cacheStorageFallingBackToLocal(config: .test())
        }

        // Then
        verify(cacheStorageFactory)
            .cacheLocalStorage()
            .called(1)
        #expect(
            alertController.warnings().map(\.message).map { $0.plain() } == [
                "No remote cache endpoint is available.",
            ]
        )
    }

    @Test func uses_the_local_cache_and_relays_why_when_the_account_refuses_the_caller() async throws {
        // Given
        let alertController = AlertController()
        let message = "You are logged in as 'stranger', which is not a member of 'acme'."
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willThrow(CacheURLStoreError.forbidden(message))

        // When
        _ = try await AlertController.$current.withValue(alertController) {
            try await cacheStorageFactory.cacheStorageFallingBackToLocal(config: .test())
        }

        // Then
        verify(cacheStorageFactory)
            .cacheLocalStorage()
            .called(1)
        #expect(alertController.warnings().map(\.message).map { $0.plain() } == [message])
    }

    @Test(arguments: [
        CacheURLStoreError.invalidURL("not a url") as Error,
        CacheURLStoreError.invalidAccountHandle(nil),
        CacheURLStoreError.missingEndpointOverride,
        RefreshAuthTokenServiceError.unauthorized("Invalid token"),
    ])
    func rethrows_errors_that_waiting_does_not_fix(error: Error) async throws {
        // Given
        given(cacheStorageFactory)
            .cacheStorage(config: .any)
            .willThrow(error)

        // When/Then
        await #expect(throws: (any Error).self) {
            try await cacheStorageFactory.cacheStorageFallingBackToLocal(config: .test())
        }
        verify(cacheStorageFactory)
            .cacheLocalStorage()
            .called(0)
    }
}
