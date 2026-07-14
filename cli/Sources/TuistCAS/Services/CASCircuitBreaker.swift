#if os(macOS)
    import Foundation
    import Logging
    import TuistCache
    import TuistLogging

    /// A token for one remote attempt, tied to the breaker generation that was
    /// current when the attempt began. Results from a superseded generation (a
    /// request that was already in flight when the breaker opened) are ignored, so a
    /// late straggler cannot flip the breaker state.
    public struct CASAttempt: Sendable {
        fileprivate let generation: Int
    }

    /// A per-process circuit breaker for the remote CAS backend.
    ///
    /// A build issues thousands of CAS load/save calls, many concurrently. When
    /// the remote cache is unavailable, without a breaker every call independently
    /// waits for its own failure/timeout before the compiler falls back to a local
    /// build — turning a single outage into a per-request tax that can stall or
    /// dramatically slow the whole build. The breaker lets the first few failures
    /// trip a shared switch so every subsequent call short-circuits to a local
    /// build instantly, and re-probes after a cooldown so caching resumes if the
    /// backend recovers mid-build (e.g. after a pod roll).
    ///
    /// It never changes build output: a short-circuited load behaves like a cache
    /// miss (the compiler builds locally) and a short-circuited save skips the
    /// upload (the artifact is already built locally). The breaker only decides
    /// *when to stop asking* a backend that is already answering with failures.
    ///
    /// Every attempt is scoped to a generation. Opening the breaker bumps the
    /// generation, so results from requests that were already in flight at that
    /// moment are discarded rather than allowed to close it — otherwise, with many
    /// concurrent requests, one late hit could re-enable the remote before the
    /// cooldown and defeat the "trip once, short-circuit the rest" guarantee.
    public actor CASCircuitBreaker {
        private enum State {
            case closed
            case open(until: Date)
            case halfOpen
        }

        private let failureThreshold: Int
        private let cooldown: TimeInterval
        private let now: @Sendable () -> Date
        private var state: State = .closed
        private var consecutiveFailures = 0
        private var probeInFlight = false
        private var generation = 0

        /// - Parameters:
        ///   - failureThreshold: consecutive failures before the breaker opens.
        ///   - cooldown: how long the breaker stays open before allowing a single
        ///     probe. Short so a long build resumes caching soon after a transient
        ///     blip, rather than losing the remote cache for its whole duration.
        ///   - now: injectable clock for tests.
        public init(
            failureThreshold: Int = 5,
            cooldown: TimeInterval = 30,
            now: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.failureThreshold = failureThreshold
            self.cooldown = cooldown
            self.now = now
        }

        /// Begins a remote attempt, returning a token when one is allowed and `nil`
        /// when the breaker is open (the caller then skips the remote and falls back
        /// locally). When the cooldown elapses it allows a single probe (half-open)
        /// and blocks other callers until that probe resolves, so a recovering
        /// backend is not stampeded. Callers must feed the token back into exactly
        /// one of `recordSuccess`, `recordFailure`, or `release`.
        public func attempt() -> CASAttempt? {
            switch state {
            case .closed:
                return CASAttempt(generation: generation)
            case .halfOpen:
                if probeInFlight { return nil }
                probeInFlight = true
                return CASAttempt(generation: generation)
            case let .open(until):
                if now() >= until {
                    state = .halfOpen
                    probeInFlight = true
                    return CASAttempt(generation: generation)
                }
                return nil
            }
        }

        /// Records a reachable backend for this attempt (a hit or a miss both
        /// count): resets the failure run and closes the breaker. A stale result
        /// (from a superseded generation) is ignored.
        public func recordSuccess(_ attempt: CASAttempt) {
            guard attempt.generation == generation else { return }
            let wasClosed = isClosed
            consecutiveFailures = 0
            probeInFlight = false
            state = .closed
            if !wasClosed {
                Logger.current.info("Remote cache recovered; re-enabled for this build.")
            }
        }

        /// Records an unavailable backend for this attempt (5xx / timeout /
        /// connection / auth error). Trips the breaker once `failureThreshold`
        /// consecutive failures accumulate, or immediately re-opens if a half-open
        /// probe failed. A stale result (from a superseded generation) is ignored.
        public func recordFailure(_ attempt: CASAttempt) {
            guard attempt.generation == generation else { return }
            probeInFlight = false
            consecutiveFailures += 1
            switch state {
            case .halfOpen:
                open()
            case .closed:
                if consecutiveFailures >= failureThreshold {
                    open()
                }
            case .open:
                break
            }
        }

        /// Releases an attempt that was abandoned before reaching the backend (e.g.
        /// a local error), freeing a half-open probe slot without recording a
        /// backend-health outcome.
        public func release(_ attempt: CASAttempt) {
            guard attempt.generation == generation else { return }
            probeInFlight = false
        }

        /// Whether the breaker is currently blocking remote attempts. Exposed for
        /// tests and diagnostics; gating goes through `attempt()`, which also
        /// advances an elapsed cooldown.
        public var isOpen: Bool {
            if case .open = state { return true }
            return false
        }

        private var isClosed: Bool {
            if case .closed = state { return true }
            return false
        }

        private func open() {
            let alreadyOpen = !isClosed
            generation += 1
            state = .open(until: now().addingTimeInterval(cooldown))
            if !alreadyOpen {
                Logger.current.warning(
                    "Remote cache unavailable after \(consecutiveFailures) consecutive failures; falling back to local builds for this build (retrying in \(Int(cooldown))s)."
                )
            }
        }
    }

    /// Classifies a thrown CAS error as a backend-health signal. Errors that mean
    /// "the backend answered, this particular request just can't be served" — a 404
    /// miss, or an artifact too large to upload — leave the breaker closed; every
    /// other error (5xx, timeout, connection failure, auth) counts as unavailable.
    func casErrorIsBackendHealthy(_ error: Error) -> Bool {
        if let error = error as? LoadCacheCASServiceError, case .notFound = error {
            return true
        }
        if let error = error as? SaveCacheCASServiceError, case .contentTooLarge = error {
            return true
        }
        return false
    }
#endif
