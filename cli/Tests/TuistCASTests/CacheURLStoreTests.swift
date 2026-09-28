import Foundation
import Mockable
import Testing
import TuistEnvironment
import TuistServer
import TuistTesting

@testable import TuistCAS

struct CacheURLStoreTests {
    private let service = MockGetCacheEndpointServicing()
    private let subject: CacheURLStore

    init() {
        subject = CacheURLStore(getCacheEndpointService: service, configurationCache: CachedValueStore())
    }

    @Test(.withMockedEnvironment(), arguments: [
        ("https://tuist.dev", "acme.cache.tuist.dev"),
        ("https://tuist.io", "acme.cache.tuist.dev"),
        ("https://tuist.dev:443/", "acme.cache.tuist.dev"),
        ("https://canary.tuist.dev", "acme-canary.cache.tuist.dev"),
        ("https://staging.tuist.dev", "acme-staging.cache.tuist.dev"),
    ])
    func derivesHostedHostname(server: String, host: String) async throws {
        let serverURL = try #require(URL(string: server))
        let result = try await subject.getCacheURL(for: serverURL, accountHandle: "Acme")
        #expect(result.absoluteString == "https://\(host)")
        #expect(try await subject.getCacheURL(for: serverURL, accountHandle: "Acme") == result)
        verify(service).getCacheEndpoint(serverURL: .any).called(0)
    }

    @Test(.withMockedEnvironment(), arguments: [
        "https://self-hosted.example.com", "http://localhost:8080", "https://tuist.dev.example.com",
        "https://tuist.dev:8080", "https://tuist.dev/custom", "http://tuist.dev",
    ])
    func discoversMainEndpointForOtherServers(server: String) async throws {
        given(service).getCacheEndpoint(serverURL: .value(URL(string: server)!))
            .willReturn(CacheEndpointResolution(endpoint: "https://main.example.com/cache", maxAge: 60))
        let result = try await subject.getCacheURL(for: URL(string: server)!, accountHandle: nil)
        #expect(result.absoluteString == "https://main.example.com/cache")
        #expect(try await subject.getCacheURL(for: URL(string: server)!, accountHandle: "another-account") == result)
        verify(service).getCacheEndpoint(serverURL: .any).called(1)
    }

    @Test(.withMockedEnvironment(), arguments: [
        nil, "", "../acme", "acme/project", "acme.example", "acme@evil", "-acme", "acme-",
        "acme-staging", "acme-canary", "acme\n", String(repeating: "a", count: 33),
    ] as [String?])
    func rejectsInvalidOrReservedHandles(handle: String?) async throws {
        await #expect(throws: CacheURLStoreError.invalidAccountHandle(handle)) {
            try await subject.getCacheURL(for: URL(string: "https://tuist.dev")!, accountHandle: handle)
        }
    }

    @Test(.withMockedEnvironment(), arguments: ["a", "acme-42", String(repeating: "a", count: 32)])
    func acceptsValidHandles(handle: String) async throws {
        let result = try await subject.getCacheURL(for: URL(string: "https://tuist.dev")!, accountHandle: handle)
        #expect(result.host == "\(handle).cache.tuist.dev")
    }

    @Test(.withMockedEnvironment(), arguments: ["https://private.example.com/cache", "http://localhost:8081"])
    func explicitOverrideTakesPrecedence(endpoint: String) async throws {
        Environment.mocked?.variables["TUIST_CACHE_ENDPOINT"] = endpoint
        let url = try await subject.getCacheURL(for: URL(string: "https://tuist.dev")!, accountHandle: nil)
        #expect(url.absoluteString == endpoint)
        verify(service).getCacheEndpoint(serverURL: .any).called(0)
        #expect(try await subject
            .getCacheURL(for: URL(string: "https://private.example.com")!, accountHandle: nil) == url)
    }

    @Test(.withMockedEnvironment(), arguments: ["", "/relative", "ftp://cache.example.com", "https://"])
    func rejectsInvalidOverrides(endpoint: String) async throws {
        Environment.mocked?.variables["TUIST_CACHE_ENDPOINT"] = endpoint
        await #expect(throws: CacheURLStoreError.invalidURL(endpoint)) {
            try await subject.getCacheURL(for: URL(string: "https://tuist.dev")!, accountHandle: "acme")
        }
    }

    @Test(.withMockedEnvironment())
    func emptyDiscoveryUsesLocalFallbackWithoutDerivingManagedURL() async throws {
        service.reset()
        given(service).getCacheEndpoint(serverURL: .any)
            .willReturn(CacheEndpointResolution(endpoint: nil, maxAge: 5))
        for _ in 0 ..< 2 {
            await #expect(throws: CacheURLStoreError.noEndpointsAvailable) {
                try await subject.getCacheURL(for: URL(string: "https://self-hosted.example.com")!, accountHandle: "acme")
            }
        }
        verify(service).getCacheEndpoint(serverURL: .any).called(1)
    }

    @Test(.withMockedEnvironment())
    func refreshesExpiredConfiguration() async throws {
        service.reset()
        given(service).getCacheEndpoint(serverURL: .any)
            .willReturn(CacheEndpointResolution(endpoint: "https://cache.example.com", maxAge: 0))
        for _ in 0 ..< 2 {
            _ = try await subject.getCacheURL(for: URL(string: "https://self-hosted.example.com")!, accountHandle: "acme")
        }
        verify(service).getCacheEndpoint(serverURL: .any).called(2)
    }

    @Test(.withMockedEnvironment(), arguments: [404, 503])
    func discoveryFailureDoesNotDeriveManagedURL(status: Int) async throws {
        service.reset()
        given(service).getCacheEndpoint(serverURL: .any)
            .willThrow(GetCacheEndpointServiceError.unknownError(status))
        await #expect(throws: GetCacheEndpointServiceError.unknownError(status)) {
            try await subject.getCacheURL(for: URL(string: "https://self-hosted.example.com")!, accountHandle: "acme")
        }
    }

    @Test(.withMockedEnvironment())
    func rejectsInvalidDiscoveredEndpoint() async throws {
        service.reset()
        given(service).getCacheEndpoint(serverURL: .any)
            .willReturn(CacheEndpointResolution(endpoint: "ftp://cache.example.com", maxAge: 60))
        await #expect(throws: CacheURLStoreError.invalidURL("ftp://cache.example.com")) {
            try await subject.getCacheURL(for: URL(string: "https://self-hosted.example.com")!, accountHandle: "acme")
        }
    }
}
