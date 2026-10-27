import Foundation
import GRPCCore

/// How long a call keeps retrying a Kura replica's drain refusal. A draining replica answers every
/// call with `UNAVAILABLE: server is draining` until it exits, 20 s later in a hosted rollout, but
/// endpoint and ingress propagation take seconds, so a refusal is retried for `window` and a client
/// that never reaches a serving replica fails after it instead of stalling for the rest of the drain.
/// The first retry is immediate, then 250 ms doubling to a 1 s cap. Refusals do not use up a call's
/// ordinary attempts.
struct REAPIDrainRetryLadder {
    static let window: Duration = .seconds(5)
    static let backoff: Duration = .milliseconds(250)
    static let maximumBackoff: Duration = .seconds(1)
    private static let message = "server is draining"

    private var refusals = 0
    private var drainingSince: ContinuousClock.Instant?

    /// The activation gateway holds a request for its own activation window, so its answer is never a
    /// drain refusal, whatever its message: each retry would wait out that window again.
    static func isDrainRefusal(_ error: any Error) -> Bool {
        guard let error = error as? RPCError, error.code == .unavailable, error.message == message else { return false }
        return !error.metadata[stringValues: "x-tuist-cache-activation"].contains("pending")
    }

    /// The wait before retrying a drain refusal received at `now`, or `nil` once the window is spent.
    mutating func nextDelay(now: ContinuousClock.Instant = .now) -> Duration? {
        let drainingSince = drainingSince ?? now
        self.drainingSince = drainingSince
        let remaining = Self.window - (now - drainingSince)
        guard remaining > .zero else { return nil }
        let delay = refusals == 0 ? .zero : min(Self.backoff * (1 << min(refusals - 1, 8)), Self.maximumBackoff)
        refusals += 1
        return min(delay, remaining)
    }
}
