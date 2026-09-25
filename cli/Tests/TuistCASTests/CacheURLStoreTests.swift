import Foundation
import Testing
import TuistEnvironment
import TuistTesting

@testable import TuistCAS

struct CacheURLStoreTests {
    private let subject = CacheURLStore()

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
    }

    @Test(.withMockedEnvironment(), arguments: [
        "https://self-hosted.example.com", "http://localhost:8080", "https://tuist.dev.example.com",
        "https://tuist.dev:8080", "https://tuist.dev/custom", "http://tuist.dev",
    ])
    func requiresExplicitEndpointForOtherServers(server: String) async throws {
        let serverURL = try #require(URL(string: server))
        await #expect(throws: CacheURLStoreError.missingEndpointOverride) {
            try await subject.getCacheURL(for: serverURL, accountHandle: "acme")
        }
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
}
