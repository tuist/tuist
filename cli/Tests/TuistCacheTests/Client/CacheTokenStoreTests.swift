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

    /// A server that cannot mint a token stays that way, and a build makes
    /// thousands of cache calls, so retrying on each one would put a failing
    /// round-trip in front of every request against an older deployment.
    @Test func does_not_retry_the_exchange_while_the_cooldown_holds() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willThrow(UnavailableError())
        let subject = CacheTokenStore(getCacheTokenService: service)

        // When
        var tokens: [String?] = []
        for _ in 0 ..< 50 {
            await tokens.append(
                subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")
            )
        }

        // Then
        #expect(tokens.allSatisfy { $0 == nil })
        verify(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .called(1)
    }

    /// The cooldown suppresses retries, it does not stop them, so a server
    /// upgraded mid-build starts minting tokens without restarting the CLI.
    @Test func retries_the_exchange_once_the_cooldown_lapses() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willThrow(UnavailableError())
        let clock = MutableClock(Date())
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            now: { clock.now }
        )

        // When
        _ = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")
        clock.advance(by: 61)
        _ = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")

        // Then
        verify(service)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .called(2)
    }

    /// A token that arrives after an earlier failure has to clear the cooldown,
    /// or a later refresh would be suppressed by a stale entry.
    @Test func stops_holding_back_retries_once_an_exchange_succeeds() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = FlakyCacheTokenService()
        let clock = MutableClock(Date())
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            now: { clock.now }
        )

        // When
        _ = await subject.cacheToken(authenticationURL: authenticationURL, projectHandle: "acme/ios")
        clock.advance(by: 61)
        let recovered = await subject.cacheToken(
            authenticationURL: authenticationURL,
            projectHandle: "acme/ios"
        )
        // Past the token's lifetime, so this needs a fresh exchange rather than
        // the cooldown left behind by the first failure.
        clock.advance(by: 1800)
        let refreshed = await subject.cacheToken(
            authenticationURL: authenticationURL,
            projectHandle: "acme/ios"
        )

        // Then
        #expect(recovered == "cache-token")
        #expect(refreshed == "cache-token")
        #expect(await service.callCount == 3)
    }
}

/// Lets a test move past the cooldown without sleeping through it.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

private actor FlakyCacheTokenService: GetCacheTokenServicing {
    struct UnavailableError: Error {}

    private(set) var callCount = 0

    func getCacheToken(serverURL _: URL, projectHandle _: String?) async throws -> CacheToken {
        callCount += 1
        if callCount == 1 { throw UnavailableError() }
        return CacheToken(token: "cache-token", expiresIn: 1800)
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
