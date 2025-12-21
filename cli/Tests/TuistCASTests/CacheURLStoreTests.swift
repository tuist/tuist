import Foundation
import Mockable
import Testing
import TuistServer
import TuistSupport

@testable import TuistCAS

@Suite struct CacheURLStoreTests {
    private let subject: CacheURLStore
    private let getCacheEndpoints = MockGetCacheEndpointsServicing()
    private let latencyService = MockEndpointLatencyServicing()
    private let cachedValueStore = CachedValueStore(backend: .inSystemProcess)

    init() {
        subject = CacheURLStore(
            cachedValueStore: cachedValueStore,
            getCacheEndpointsService: getCacheEndpoints,
            endpointLatencyService: latencyService
        )
    }

    @Test(.withMockedEnvironment())
    func returns_cached_url_when_cache_populated() async throws {
        // Given
        let serverURL = URL(string: "https://tuist.dev")!
        let endpoint = "https://cache.example.com"
        let endpointTwo = "https://cache.example.two.com"

        given(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .willReturn([endpoint, endpointTwo])

        given(latencyService)
            .measureLatency(for: .value(URL(string: endpoint)!))
            .willReturn(0.123)

        given(latencyService)
            .measureLatency(for: .value(URL(string: endpointTwo)!))
            .willReturn(0.243)

        _ = try await subject.getCacheURL(for: serverURL, accountHandle: nil)

        // When - second call should use cache
        let result = try await subject.getCacheURL(for: serverURL, accountHandle: nil)

        // Then
        #expect(result.absoluteString == endpoint)
        verify(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func uses_single_endpoint_directly_without_measuring_latency() async throws {
        // Given
        let serverURL = URL(string: "https://tuist.dev")!
        let endpoint = "https://cache.example.com"

        given(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .willReturn([endpoint])

        // When
        let result = try await subject.getCacheURL(for: serverURL, accountHandle: nil)

        // Then
        #expect(result.absoluteString == endpoint)
        verify(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .called(1)
        // Should NOT measure latency for single endpoint
        verify(latencyService)
            .measureLatency(for: .any)
            .called(0)
    }

    @Test(.withMockedEnvironment())
    func selects_endpoint_with_lowest_latency() async throws {
        // Given
        let serverURL = URL(string: "https://tuist.dev")!
        let slowEndpoint = "https://slow.example.com"
        let fastEndpoint = "https://fast.example.com"
        let mediumEndpoint = "https://medium.example.com"

        given(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .willReturn([slowEndpoint, fastEndpoint, mediumEndpoint])

        given(latencyService)
            .measureLatency(for: .value(URL(string: slowEndpoint)!))
            .willReturn(0.500)

        given(latencyService)
            .measureLatency(for: .value(URL(string: fastEndpoint)!))
            .willReturn(0.050)

        given(latencyService)
            .measureLatency(for: .value(URL(string: mediumEndpoint)!))
            .willReturn(0.200)

        // When
        let result = try await subject.getCacheURL(for: serverURL, accountHandle: nil)

        // Then
        #expect(result.absoluteString == fastEndpoint)
    }

    @Test(.withMockedEnvironment())
    func filters_unreachable_endpoints_and_selects_best() async throws {
        // Given
        let serverURL = URL(string: "https://tuist.dev")!
        let unreachableEndpoint = "https://unreachable.example.com"
        let reachableEndpoint = "https://reachable.example.com"

        given(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .willReturn([unreachableEndpoint, reachableEndpoint])

        given(latencyService)
            .measureLatency(for: .value(URL(string: unreachableEndpoint)!))
            .willReturn(nil)

        given(latencyService)
            .measureLatency(for: .value(URL(string: reachableEndpoint)!))
            .willReturn(0.123)

        // When
        let result = try await subject.getCacheURL(for: serverURL, accountHandle: nil)

        // Then
        #expect(result.absoluteString == reachableEndpoint)
    }

    @Test(.withMockedEnvironment())
    func throws_when_all_endpoints_unreachable() async throws {
        // Given
        let serverURL = URL(string: "https://tuist.dev")!
        let endpoint1 = "https://endpoint1.example.com"
        let endpoint2 = "https://endpoint2.example.com"

        given(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .willReturn([endpoint1, endpoint2])

        given(latencyService)
            .measureLatency(for: .any)
            .willReturn(nil)

        // When/Then
        await #expect(throws: CacheURLStoreError.noReachableEndpoints) {
            _ = try await subject.getCacheURL(for: serverURL, accountHandle: nil)
        }
    }

    @Test(.withMockedEnvironment())
    func throws_when_no_endpoints_available() async throws {
        // Given
        let serverURL = URL(string: "https://tuist.dev")!

        given(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
            .willReturn([])

        // When/Then
        await #expect(throws: CacheURLStoreError.noEndpointsAvailable) {
            _ = try await subject.getCacheURL(for: serverURL, accountHandle: nil)
        }
    }

    @Test(.withMockedEnvironment())
    func uses_account_handle_for_cache_key() async throws {
        // Given
        let serverURL = URL(string: "https://tuist.dev")!
        let endpoint = "https://cache.example.com"
        let accountHandle = "my-org"

        given(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(accountHandle))
            .willReturn([endpoint])

        // When
        let result = try await subject.getCacheURL(for: serverURL, accountHandle: accountHandle)

        // Then
        #expect(result.absoluteString == endpoint)
        verify(getCacheEndpoints)
            .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(accountHandle))
            .called(1)
    }
}
