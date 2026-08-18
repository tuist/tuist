#if os(macOS)
    import Foundation
    import Mockable
    import Testing
    import TuistEnvironment
    import TuistServer
    import TuistTesting

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

        @Test
        func treats_a_missing_endpoint_as_transient_and_a_malformed_one_as_fatal() {
            // An account whose instance was reclaimed for inactivity, and one whose
            // instance is still rolling out, both resolve on their own once the
            // server provisions an endpoint back. A malformed URL never does, so it
            // must stay fatal: the cache daemon starts through the first two and
            // refuses the third.
            #expect(CacheURLStoreError.noEndpointsAvailable.isTransientAbsence)
            #expect(CacheURLStoreError.noReachableEndpoints.isTransientAbsence)
            #expect(!CacheURLStoreError.invalidURL("not a url").isTransientAbsence)
        }

        @Test(.withMockedEnvironment())
        func does_not_cache_a_failed_lookup_so_a_returning_instance_is_picked_up() async throws {
            // Given
            // Two stores over one shared cache stand in for two requests to the
            // same long-lived cache daemon: the first while the account's instance
            // is still being provisioned back, the second once it is serving. If a
            // failed lookup were cached, the daemon would need a restart to ever
            // see the instance again.
            let serverURL = URL(string: "https://tuist.dev")!
            let endpoint = "https://cache.example.com"

            let whileProvisioning = MockGetCacheEndpointsServicing()
            given(whileProvisioning)
                .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
                .willReturn([])

            let onceServing = MockGetCacheEndpointsServicing()
            given(onceServing)
                .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
                .willReturn([endpoint])

            let provisioningSubject = CacheURLStore(
                cachedValueStore: cachedValueStore,
                getCacheEndpointsService: whileProvisioning,
                endpointLatencyService: latencyService
            )
            let servingSubject = CacheURLStore(
                cachedValueStore: cachedValueStore,
                getCacheEndpointsService: onceServing,
                endpointLatencyService: latencyService
            )

            await #expect(throws: CacheURLStoreError.noEndpointsAvailable) {
                _ = try await provisioningSubject.getCacheURL(for: serverURL, accountHandle: nil)
            }

            // When
            let url = try await servingSubject.getCacheURL(for: serverURL, accountHandle: nil)

            // Then
            #expect(url == URL(string: endpoint)!)
        }

        @Test(.withMockedEnvironment())
        func uses_account_handle_for_cache_key() async throws {
            // Given
            let serverURL = URL(string: "https://tuist.dev")!
            let endpoint = "https://cache.example.com"
            let accountHandle = "my-org"

            given(getCacheEndpoints)
                .getCacheEndpoints(
                    serverURL: .value(serverURL),
                    accountHandle: .value(accountHandle)
                )
                .willReturn([endpoint])

            // When
            let result = try await subject.getCacheURL(for: serverURL, accountHandle: accountHandle)

            // Then
            #expect(result.absoluteString == endpoint)
            verify(getCacheEndpoints)
                .getCacheEndpoints(
                    serverURL: .value(serverURL),
                    accountHandle: .value(accountHandle)
                )
                .called(1)
        }

        @Test(.withMockedEnvironment())
        func uses_override_endpoint_when_environment_variable_set() async throws {
            // Given
            let serverURL = URL(string: "https://tuist.dev")!
            let overrideEndpoint = "https://override.example.com"
            Environment.mocked?.variables["TUIST_CACHE_ENDPOINT"] = overrideEndpoint

            // When
            let result = try await subject.getCacheURL(for: serverURL, accountHandle: nil)

            // Then
            #expect(result.absoluteString == overrideEndpoint)
            verify(getCacheEndpoints)
                .getCacheEndpoints(serverURL: .any, accountHandle: .any)
                .called(0)
            verify(latencyService)
                .measureLatency(for: .any)
                .called(0)
        }

        @Test(.withMockedEnvironment())
        func throws_when_override_endpoint_is_invalid_url() async throws {
            // Given
            let serverURL = URL(string: "https://tuist.dev")!
            Environment.mocked?.variables["TUIST_CACHE_ENDPOINT"] = ""

            // When/Then
            await #expect(throws: CacheURLStoreError.invalidURL("")) {
                _ = try await subject.getCacheURL(for: serverURL, accountHandle: nil)
            }
        }

        @Test(.withMockedEnvironment())
        func separates_cached_endpoints_when_kura_feature_flag_is_enabled() async throws {
            // Given
            let serverURL = URL(string: "https://tuist.dev")!
            let defaultEndpoint = "https://cache.example.com"
            let kuraEndpoint = "https://kura-cache.example.com"
            let kuraGetCacheEndpoints = MockGetCacheEndpointsServicing()
            let kuraSubject = CacheURLStore(
                cachedValueStore: cachedValueStore,
                getCacheEndpointsService: kuraGetCacheEndpoints,
                endpointLatencyService: latencyService
            )

            given(getCacheEndpoints)
                .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
                .willReturn([defaultEndpoint])

            // When
            let defaultResult = try await subject.getCacheURL(for: serverURL, accountHandle: nil)
            Environment.mocked?.variables["TUIST_FEATURE_FLAG_KURA"] = "1"
            given(kuraGetCacheEndpoints)
                .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
                .willReturn([kuraEndpoint])
            let kuraResult = try await kuraSubject.getCacheURL(for: serverURL, accountHandle: nil)

            // Then
            #expect(defaultResult.absoluteString == defaultEndpoint)
            #expect(kuraResult.absoluteString == kuraEndpoint)
            verify(getCacheEndpoints)
                .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
                .called(1)
            verify(kuraGetCacheEndpoints)
                .getCacheEndpoints(serverURL: .value(serverURL), accountHandle: .value(nil))
                .called(1)
        }
    }
#endif
