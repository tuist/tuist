import Foundation
import Mockable
import Synchronization
import Testing
import TuistAlert
import TuistServer
import TuistTesting

@testable import TuistCache

struct CacheTokenStoreTests {
    private let authenticationURL = URL(string: "https://auth.tuist.dev")!

    @Test func returns_the_exchanged_token() async throws {
        // Given
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .willReturn(CacheToken(token: "cache-token", expiresIn: 1800))
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When
        let token = try await subject.cacheToken(
            authenticationURL: authenticationURL,
            fullHandle: "acme/ios"
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
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .willReturn(CacheToken(token: "cache-token", expiresIn: 1800))
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When
        for _ in 0 ..< 5 {
            _ = try await subject.cacheToken(
                authenticationURL: authenticationURL,
                fullHandle: "acme/ios"
            )
        }

        // Then
        verify(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .called(1)
    }

    /// The margin is 60s, so a token this short-lived is already stale when it
    /// arrives and must not be handed out a second time.
    @Test func exchanges_again_once_the_token_is_close_to_expiring() async throws {
        // Given
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .willReturn(CacheToken(token: "cache-token", expiresIn: 10))
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When
        _ = try await subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/ios")
        _ = try await subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/ios")

        // Then
        verify(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .called(2)
    }

    @Test func keeps_tokens_for_different_projects_apart() async throws {
        // Given
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, fullHandle: .value("acme/ios"))
            .willReturn(CacheToken(token: "ios-token", expiresIn: 1800))
        given(service)
            .getCacheToken(serverURL: .any, fullHandle: .value("acme/android"))
            .willReturn(CacheToken(token: "android-token", expiresIn: 1800))
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When
        let ios = try await subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/ios")
        let android = try await subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/android")

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
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When
        let tokens = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    try await subject.cacheToken(
                        authenticationURL: URL(string: "https://auth.tuist.dev")!,
                        fullHandle: "acme/ios"
                    )
                }
            }
            return try await group.reduce(into: [String?]()) { $0.append($1) }
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
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .willThrow(UnavailableError())
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When
        let token = try await subject.cacheToken(
            authenticationURL: authenticationURL,
            fullHandle: "acme/ios"
        )

        // Then
        #expect(token == nil)
    }

    /// An account over its plan's free tier is refused by cache nodes too, and a
    /// credential minted before it crossed the threshold can still carry
    /// locally verifiable grants, so falling back to that credential would keep
    /// the cache reachable past the point the server refused to mint for it.
    @Test(.withMockedDependencies()) func refuses_to_fall_back_when_the_free_tier_is_exhausted() async throws {
        // Given
        let message = "The account 'acme' has reached the limits of the plan 'Tuist Air'."
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .willThrow(GetCacheTokenServiceError.freeTierExhausted(message))
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When / Then
        await #expect(throws: GetCacheTokenServiceError.self) {
            try await subject.cacheToken(
                authenticationURL: authenticationURL,
                fullHandle: "acme/ios"
            )
        }

        // The refusal sticks, rather than lapsing into the credential fallback
        // the way an unreachable exchange does.
        await #expect(throws: GetCacheTokenServiceError.self) {
            try await subject.cacheToken(
                authenticationURL: authenticationURL,
                fullHandle: "acme/ios"
            )
        }

        #expect(
            AlertController.current.warnings().map(\.message).map { $0.plain() } == [message]
        )
    }

    /// A server that cannot mint a token stays that way, and a build makes
    /// thousands of cache calls, so retrying on each one would put a failing
    /// round-trip in front of every request against an older deployment.
    @Test func does_not_exchange_again_while_the_server_is_known_unavailable() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .willThrow(UnavailableError())
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess)
        )

        // When
        var tokens: [String?] = []
        for _ in 0 ..< 50 {
            try await tokens.append(
                subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/ios")
            )
        }

        // Then
        #expect(tokens.allSatisfy { $0 == nil })
        verify(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .called(1)
    }

    /// Unavailability is remembered for a while, not forever, so a server
    /// upgraded mid-build starts minting tokens without restarting the CLI.
    @Test func exchanges_again_once_the_unavailability_lapses() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = MockGetCacheTokenServicing()
        given(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .willThrow(UnavailableError())
        let clock = MutableClock(Date())
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess),
            now: { clock.now }
        )

        // When
        _ = try await subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/ios")
        clock.advance(by: 61)
        _ = try await subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/ios")

        // Then
        verify(service)
            .getCacheToken(serverURL: .any, fullHandle: .any)
            .called(2)
    }

    /// A token that arrives after an earlier failure has to clear the recorded
    /// unavailability, or a later refresh would be suppressed by a stale entry.
    @Test func stops_holding_back_retries_once_an_exchange_succeeds() async throws {
        // Given
        struct UnavailableError: Error {}
        let service = FlakyCacheTokenService()
        let clock = MutableClock(Date())
        let subject = CacheTokenStore(
            getCacheTokenService: service,
            cachedValueStore: CachedValueStore(backend: .inSystemProcess),
            now: { clock.now }
        )

        // When
        _ = try await subject.cacheToken(authenticationURL: authenticationURL, fullHandle: "acme/ios")
        clock.advance(by: 61)
        let recovered = try await subject.cacheToken(
            authenticationURL: authenticationURL,
            fullHandle: "acme/ios"
        )
        // The token it hands back is already past the refresh margin, so this
        // needs a fresh exchange and would be blocked by the unavailability the earlier
        // failure left behind.
        let refreshed = try await subject.cacheToken(
            authenticationURL: authenticationURL,
            fullHandle: "acme/ios"
        )

        // Then
        #expect(recovered == "cache-token")
        #expect(refreshed == "cache-token")
        #expect(await service.callCount == 3)
    }
}

/// Lets a test move past the recorded unavailability without sleeping through it.
private final class MutableClock: Sendable {
    private let date: Mutex<Date>

    init(_ date: Date) {
        self.date = Mutex(date)
    }

    var now: Date {
        date.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        date.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

private actor FlakyCacheTokenService: GetCacheTokenServicing {
    struct UnavailableError: Error {}

    private(set) var callCount = 0

    /// Short enough that the refresh margin makes every token it mints already
    /// stale, so a caller that is not held back exchanges again.
    func getCacheToken(serverURL _: URL, fullHandle _: String?) async throws -> CacheToken {
        callCount += 1
        if callCount == 1 { throw UnavailableError() }
        return CacheToken(token: "cache-token", expiresIn: 10)
    }
}

private actor SlowCacheTokenService: GetCacheTokenServicing {
    private(set) var callCount = 0

    func getCacheToken(serverURL _: URL, fullHandle _: String?) async throws -> CacheToken {
        callCount += 1
        try? await Task.sleep(nanoseconds: 100_000_000)
        return CacheToken(token: "cache-token", expiresIn: 1800)
    }
}
