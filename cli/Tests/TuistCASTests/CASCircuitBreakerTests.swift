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
            #expect(await breaker.shouldAttempt())
            #expect(await breaker.shouldAttempt())
            #expect(await breaker.isOpen == false)
        }

        @Test func opens_after_threshold_consecutive_failures() async {
            let breaker = CASCircuitBreaker(failureThreshold: 3, cooldown: 30)
            await breaker.recordFailure()
            await breaker.recordFailure()
            #expect(await breaker.isOpen == false) // below threshold
            await breaker.recordFailure()
            #expect(await breaker.isOpen)
            #expect(await breaker.shouldAttempt() == false) // within cooldown
        }

        @Test func success_resets_the_failure_run() async {
            let breaker = CASCircuitBreaker(failureThreshold: 3)
            await breaker.recordFailure()
            await breaker.recordFailure()
            await breaker.recordSuccess() // backend reachable again
            await breaker.recordFailure()
            await breaker.recordFailure()
            #expect(await breaker.isOpen == false) // counter reset, only 2 since success
        }

        @Test func success_never_opens_the_breaker() async {
            let breaker = CASCircuitBreaker(failureThreshold: 1)
            for _ in 0 ..< 10 {
                await breaker.recordSuccess()
            }
            #expect(await breaker.isOpen == false)
            #expect(await breaker.shouldAttempt())
        }

        @Test func half_open_after_cooldown_allows_a_single_probe() async {
            let clock = TestClock()
            let breaker = CASCircuitBreaker(failureThreshold: 1, cooldown: 30, now: { clock.now() })
            await breaker.recordFailure() // opens
            #expect(await breaker.shouldAttempt() == false)

            clock.advance(31) // cooldown elapsed
            #expect(await breaker.shouldAttempt()) // one probe allowed
            #expect(await breaker.shouldAttempt() == false) // probe already in flight

            await breaker.recordSuccess() // probe succeeded -> closed
            #expect(await breaker.isOpen == false)
            #expect(await breaker.shouldAttempt())
        }

        @Test func half_open_probe_failure_reopens() async {
            let clock = TestClock()
            let breaker = CASCircuitBreaker(failureThreshold: 1, cooldown: 30, now: { clock.now() })
            await breaker.recordFailure() // opens
            clock.advance(31)
            #expect(await breaker.shouldAttempt()) // probe
            await breaker.recordFailure() // probe failed -> reopen
            #expect(await breaker.isOpen)
            #expect(await breaker.shouldAttempt() == false) // cooldown restarted
            clock.advance(31)
            #expect(await breaker.shouldAttempt()) // probes again after the new cooldown
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
