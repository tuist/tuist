import Foundation
import Testing

@testable import TuistServer

struct CachingServerAuthenticationControllerTests {
    /// Reproduces the runner pathology (per-op auth resolution — a keychain read on
    /// macOS — on every CAS request) and confirms the decorator collapses it: a burst
    /// of concurrent resolutions hits the underlying controller once, not N times.
    @Test func memoizes_token_across_a_concurrent_burst() async throws {
        let expiry = Date().addingTimeInterval(3600)
        let token = AuthenticationToken.account(JWT.test(expiryDate: expiry, type: "account"))
        let serverURL = try #require(URL(string: "https://cache.tuist.dev"))
        let iterations = 500
        let perCallDelay: Duration = .milliseconds(20) // stands in for the keychain read
        let clock = ContinuousClock()

        // Baseline: the underlying controller resolves auth on every call (the bug).
        let baselineCounter = CallCounter()
        let baselineController = SlowAuthenticationController(
            counter: baselineCounter, token: token, perCallDelay: perCallDelay
        )
        let baselineStart = clock.now
        try await resolveConcurrently(baselineController, serverURL: serverURL, times: iterations)
        let baselineElapsed = clock.now - baselineStart
        let baselineCalls = await baselineCounter.value

        // Fixed: the caching decorator memoizes the token in-process.
        let cachedCounter = CallCounter()
        let cachedController = CachingServerAuthenticationController(
            wrapping: SlowAuthenticationController(
                counter: cachedCounter, token: token, perCallDelay: perCallDelay
            )
        )
        let cachedStart = clock.now
        try await resolveConcurrently(cachedController, serverURL: serverURL, times: iterations)
        let cachedElapsed = clock.now - cachedStart
        let cachedCalls = await cachedCounter.value

        print(
            """
            [repro] \(iterations) concurrent authenticationToken() calls
              baseline: underlying resolutions=\(baselineCalls)  elapsed=\(baselineElapsed)
              cached:   underlying resolutions=\(cachedCalls)  elapsed=\(cachedElapsed)
            """
        )

        // Baseline pays the underlying (keychain) cost per op; the decorator pays it once.
        #expect(baselineCalls == iterations)
        #expect(cachedCalls == 1)
        #expect(cachedElapsed < baselineElapsed)
    }

    /// A subsequent call after the entry lapses re-resolves (so refresh/rotation still runs).
    @Test func re_resolves_after_the_cached_entry_expires() async throws {
        // Project tokens get a short (300s) TTL, but an ABSENT result is not memoized —
        // so a token that appears after an initial miss is picked up on the next call.
        let counter = CallCounter()
        let controller = TogglingAuthenticationController(counter: counter)
        let subject = CachingServerAuthenticationController(wrapping: controller)
        let serverURL = try #require(URL(string: "https://cache.tuist.dev"))

        let first = try await subject.authenticationToken(serverURL: serverURL)
        let second = try await subject.authenticationToken(serverURL: serverURL)

        #expect(first == nil) // absent result not memoized
        #expect(second == .project("appeared"))
        #expect(await counter.value == 2)
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct SlowAuthenticationController: ServerAuthenticationControlling {
    let counter: CallCounter
    let token: AuthenticationToken
    let perCallDelay: Duration

    func authenticationToken(serverURL: URL) async throws -> AuthenticationToken? {
        try await authenticationToken(serverURL: serverURL, refreshIfNeeded: true)
    }

    func authenticationToken(serverURL _: URL, refreshIfNeeded _: Bool) async throws -> AuthenticationToken? {
        await counter.increment()
        try await Task.sleep(for: perCallDelay)
        return token
    }

    func refreshToken(serverURL _: URL) async throws {}
    func refreshToken(serverURL _: URL, inBackground _: Bool, locking _: Bool, forceInProcessLock _: Bool) async throws {}
}

/// Returns nil on the first resolution, then a project token — to exercise that an
/// absent result is not memoized.
private struct TogglingAuthenticationController: ServerAuthenticationControlling {
    let counter: CallCounter

    func authenticationToken(serverURL: URL) async throws -> AuthenticationToken? {
        try await authenticationToken(serverURL: serverURL, refreshIfNeeded: true)
    }

    func authenticationToken(serverURL _: URL, refreshIfNeeded _: Bool) async throws -> AuthenticationToken? {
        let n = await counter.value
        await counter.increment()
        return n == 0 ? nil : .project("appeared")
    }

    func refreshToken(serverURL _: URL) async throws {}
    func refreshToken(serverURL _: URL, inBackground _: Bool, locking _: Bool, forceInProcessLock _: Bool) async throws {}
}

private func resolveConcurrently(
    _ controller: some ServerAuthenticationControlling,
    serverURL: URL,
    times: Int
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0 ..< times {
            group.addTask { _ = try await controller.authenticationToken(serverURL: serverURL) }
        }
        try await group.waitForAll()
    }
}
