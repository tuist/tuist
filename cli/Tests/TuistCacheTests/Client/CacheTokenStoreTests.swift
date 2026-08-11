import Foundation
import Mockable
import Testing
import TuistServer

@testable import TuistCache

struct CacheTokenStoreTests {
    private let authenticationURL = URL(string: "https://auth.tuist.dev")!

    @Test func returns_the_exchanged_token() async throws {
        // Given
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willReturn(CacheToken(token: "cache-token", expiresIn: 1800))
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        let token = await subject.cacheToken(
            authenticationURL: authenticationURL,
            projectHandle: "acme/ios"
        )

        // Then
        #expect(token == "cache-token")
    }

    /// Exchanging once per request would put a round-trip back in front of every
    /// cache call, which is the cost this whole path exists to remove.
    @Test func reuses_a_live_token_instead_of_exchanging_again() async throws {
        // Given
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willReturn(CacheToken(token: "cache-token", expiresIn: 1800))
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        for _ in 0 ..< 5 {
            _ = await subject.cacheToken(
                authenticationURL: authenticationURL,
                projectHandle: "acme/ios"
            )
        }

        // Then
        verify(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .called(1)
    }

    /// The margin is 60s, so a token this short-lived is already stale when it
    /// arrives and must not be handed out a second time.
    @Test func exchanges_again_once_the_token_is_close_to_expiring() async throws {
        // Given
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willReturn(CacheToken(token: "cache-token", expiresIn: 10))
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        _ = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")
        _ = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")

        // Then
        verify(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .called(2)
    }

    @Test func keeps_tokens_for_different_projects_apart() async throws {
        // Given
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .value("acme/ios"))
            .willReturn(CacheToken(token: "ios-token", expiresIn: 1800))
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .value("acme/android"))
            .willReturn(CacheToken(token: "android-token", expiresIn: 1800))
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        let ios = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")
        let android = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/android")

        // Then
        #expect(ios == "ios-token")
        #expect(android == "android-token")
    }

    /// A build fires many cache requests at once. Without coalescing, a cold
    /// store would start an exchange for every one of them. Mockable's willProduce
    /// is synchronous, so this needs a stub that can actually be slow.
    @Test func coalesces_concurrent_exchanges_into_one() async throws {
        // Given
        let service = SlowCacheTokenService()
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        let tokens = await withTaskGroup(of: String?.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    await subject.cacheToken(
                        authenticationURL: URL(string: "https://auth.tuist.dev")!,
                        projectHandle: "acme/ios"
                    )
                }
            }
            return await group.reduce(into: [String?]()) { $0.append($1) }
        }

        // Then
        #expect(tokens.count == 20)
        #expect(tokens.allSatisfy { $0 == "cache-token" })
        #expect(await service.callCount == 1)
    }

    /// Cache nodes still accept the original credential, so a server that cannot
    /// mint one has to leave cache access working rather than fail the request.
    @Test func yields_nil_when_the_exchange_fails() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willThrow(UnavailableError())
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        let token = await subject.cacheToken(
            authenticationURL: authenticationURL,
            projectHandle: "acme/ios"
        )

        // Then
        #expect(token == nil)
    }

    @Test func retries_the_exchange_after_a_failure() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willThrow(UnavailableError())
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        _ = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")
        _ = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")

        // Then
        verify(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .called(2)
    }
}

private actor SlowCacheTokenService: GetCacheTokenServicing {
    private(set) var callCount = 0

    func getCacheToken(serverURL _: URL, projectHandle _: String?) async throws -> CacheToken {
        callCount += 1
        try? await Task.sleep(nanoseconds: 100_000_000)
        return CacheToken(token: "cache-token", expiresIn: 1800)
    }
}
