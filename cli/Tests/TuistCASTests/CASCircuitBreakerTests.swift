#if os(macOS)
    import Foundation
    import Testing
    import TuistCache
    @testable import TuistCAS

    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date
        init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) {
            current = start
        }

        func now() -> Date {
            lock.lock(); defer { lock.unlock() }; return current
        }

        func advance(_ interval: TimeInterval) {
            lock.lock(); current += interval; lock.unlock()
        }
    }

    struct CASCircuitBreakerTests {
        @Test func closed_breaker_allows_attempts() async {
            let breaker = CASCircuitBreaker()
            #expect(await breaker.attempt() != nil)
            #expect(await breaker.attempt() != nil)
            #expect(await breaker.isOpen == false)
        }

        @Test func opens_after_threshold_consecutive_failures() async throws {
            let breaker = CASCircuitBreaker(failureThreshold: 3, cooldown: 30)
            for _ in 0 ..< 2 {
                await breaker.recordFailure(try #require(await breaker.attempt()))
            }
            #expect(await breaker.isOpen == false) // below threshold
            await breaker.recordFailure(try #require(await breaker.attempt()))
            #expect(await breaker.isOpen)
            #expect(await breaker.attempt() == nil) // within cooldown
        }

        @Test func success_resets_the_failure_run() async throws {
            let breaker = CASCircuitBreaker(failureThreshold: 3)
            for _ in 0 ..< 2 {
                await breaker.recordFailure(try #require(await breaker.attempt()))
            }
            await breaker.recordSuccess(try #require(await breaker.attempt())) // backend reachable again
            for _ in 0 ..< 2 {
                await breaker.recordFailure(try #require(await breaker.attempt()))
            }
            #expect(await breaker.isOpen == false) // counter reset, only 2 since success
        }

        /// A late result from a request that was already in flight when the breaker
        /// opened must not close it — otherwise one straggler re-enables the remote
        /// before the cooldown and defeats the short-circuit.
        @Test func stale_success_from_a_superseded_generation_is_ignored() async throws {
            let breaker = CASCircuitBreaker(failureThreshold: 2, cooldown: 30)
            await breaker.recordFailure(try #require(await breaker.attempt())) // 1 failure, still closed
            let stale = try #require(await breaker.attempt()) // in-flight, obtained before open
            await breaker.recordFailure(try #require(await breaker.attempt())) // 2 failures -> opens
            #expect(await breaker.isOpen)

            await breaker.recordSuccess(stale) // stale success must not close it
            #expect(await breaker.isOpen)
            #expect(await breaker.attempt() == nil) // still within cooldown
        }

        @Test func attempt_advances_cooldown_and_allows_a_single_probe() async throws {
            let clock = TestClock()
            let breaker = CASCircuitBreaker(failureThreshold: 1, cooldown: 30, now: { clock.now() })
            await breaker.recordFailure(try #require(await breaker.attempt())) // opens
            #expect(await breaker.attempt() == nil) // within cooldown

            clock.advance(31)
            let probe = try #require(await breaker.attempt()) // cooldown elapsed -> one probe
            #expect(await breaker.attempt() == nil) // probe already in flight

            await breaker.recordSuccess(probe) // probe succeeded -> closed
            #expect(await breaker.isOpen == false)
            #expect(await breaker.attempt() != nil)
        }

        @Test func half_open_probe_failure_reopens() async throws {
            let clock = TestClock()
            let breaker = CASCircuitBreaker(failureThreshold: 1, cooldown: 30, now: { clock.now() })
            await breaker.recordFailure(try #require(await breaker.attempt())) // opens
            clock.advance(31)
            await breaker.recordFailure(try #require(await breaker.attempt())) // probe failed -> reopen
            #expect(await breaker.isOpen)
            #expect(await breaker.attempt() == nil) // cooldown restarted
            clock.advance(31)
            #expect(await breaker.attempt() != nil) // probes again after the new cooldown
        }

        @Test func release_frees_the_half_open_probe_slot() async throws {
            let clock = TestClock()
            let breaker = CASCircuitBreaker(failureThreshold: 1, cooldown: 30, now: { clock.now() })
            await breaker.recordFailure(try #require(await breaker.attempt())) // opens
            clock.advance(31)
            let probe = try #require(await breaker.attempt())
            #expect(await breaker.attempt() == nil) // probe in flight
            await breaker.release(probe) // abandoned before reaching the backend
            #expect(await breaker.attempt() != nil) // slot freed for the next attempt
        }

        @Test func classifies_miss_and_too_large_as_backend_healthy() {
            #expect(casErrorIsBackendHealthy(LoadCacheCASServiceError.notFound("miss")))
            #expect(casErrorIsBackendHealthy(SaveCacheCASServiceError.contentTooLarge("too big")))
        }

        @Test func classifies_server_and_transport_errors_as_unavailable() {
            #expect(casErrorIsBackendHealthy(LoadCacheCASServiceError.unknownError(503)) == false)
            #expect(casErrorIsBackendHealthy(LoadCacheCASServiceError.unauthorized("nope")) == false)
            #expect(casErrorIsBackendHealthy(SaveCacheCASServiceError.internalServerError("boom")) == false)
            #expect(casErrorIsBackendHealthy(URLError(.timedOut)) == false)
            #expect(casErrorIsBackendHealthy(URLError(.cannotConnectToHost)) == false)
        }
    }
#endif
