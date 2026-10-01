import Foundation
import Synchronization

/// Routes each call to whichever client currently holds the fewest in-flight RPCs, with a
/// cooldown and half-open probation on clients whose last RPC failed in a way that suggests the
/// underlying connection, not the request, is at fault.
///
/// Round-robin selection sends a retry back to a wedged connection as soon as its failed RPC
/// drops out of flight: the dead client reaches 0 before everyone else, becomes the unique
/// minimum, and attracts the retry. A cooldown alone would not be enough either, because
/// keepalive only pings while streams are open — the cooldown drains the connection, so a
/// silently dead peer survives it. The selector therefore combines two guards:
///
///   - A time-based cooldown that treats the client as unhealthy for a window, keeping new
///     RPCs away from it long enough for the OS or peer to clean up.
///   - Half-open probation after the cooldown expires: the first RPC after expiry runs alone
///     on the client; if it succeeds, probation clears; if it fails, the client cools again.
///     Prevents a dead-but-cooled-down connection from attracting a flood when its cooldown
///     expires with a stale in-flight count of zero.
///
/// Scoped via `withClient`: the in-flight counter decrements in `defer` so throw and cancel
/// paths release it too; a thrown error the caller says should penalize the connection records
/// a cooldown on that client's index; a return without a throw clears probation.
final class LeastOutstandingSelector<Client: Sendable>: Sendable {
    struct Cooldown: Sendable {
        /// How long a client is treated as unhealthy after a connection-shaped failure.
        /// Half-open probation is what actually proves the connection has recovered, so the
        /// duration is a drain-and-wait window, not a healing timer. Keep it long enough that
        /// a stuck RPC's deadline has clearly passed before the probation probe runs.
        var duration: Duration = .seconds(45)

        /// Virtual in-flight inflation applied to a cooled or already-probing client's
        /// effective count. Big enough to dominate any realistic in-flight count across a
        /// transfer concurrency of 32, so an unhealthy client is never picked while a healthy
        /// one is available.
        var penalty: Int = 1_000_000

        static var `default`: Cooldown { Cooldown() }
    }

    private struct State {
        var inFlight: [Int]
        var cooledUntil: [ContinuousClock.Instant?]
        /// True from the end of cooldown until the next successful RPC on this client.
        /// During probation the client admits at most one in-flight RPC, so the client is
        /// not refilled all at once when its cooldown ends.
        var probationary: [Bool]
        var rotation: Int
    }

    let clients: [Client]
    private let state: Mutex<State>
    private let cooldown: Cooldown

    init(_ clients: [Client], cooldown: Cooldown = .default) {
        precondition(!clients.isEmpty, "LeastOutstandingSelector requires at least one client")
        self.clients = clients
        self.cooldown = cooldown
        state = Mutex(State(
            inFlight: Array(repeating: 0, count: clients.count),
            cooledUntil: Array(repeating: nil, count: clients.count),
            probationary: Array(repeating: false, count: clients.count),
            rotation: 0
        ))
    }

    /// Reserves a client, runs `operation` with it, and releases the reservation when the
    /// operation returns, throws, or is cancelled. `shouldPenalize(error)` opts a specific
    /// error class into cooldown, so a `.notFound` or `.permissionDenied` does not get the
    /// same treatment as `.deadlineExceeded` or `.unavailable`. A return without a throw
    /// clears probation on the reserved client, confirming the connection is healthy.
    func withClient<T: Sendable>(
        shouldPenalize: @Sendable (any Error) -> Bool = { _ in false },
        _ operation: (Client) async throws -> T
    ) async throws -> T {
        let index = reserve()
        defer { release(index) }
        do {
            let result = try await operation(clients[index])
            recordSuccess(index)
            return result
        } catch {
            if shouldPenalize(error) { recordFailure(index) }
            throw error
        }
    }

    /// Snapshot of in-flight counts, for tests and observability. Does not include the cooldown
    /// penalty — this is the real number of RPCs currently reserved.
    var inFlight: [Int] { state.withLock { $0.inFlight } }

    private func reserve() -> Int {
        state.withLock { state -> Int in
            let now = ContinuousClock.now
            func effectiveCount(_ i: Int) -> Int {
                if let until = state.cooledUntil[i], now < until { return cooldown.penalty }
                // While probationary, only one RPC may be in flight: the probe. Further picks
                // are repelled until the probe completes, so a dead peer cannot be re-flooded
                // the instant its cooldown expires.
                if state.probationary[i], state.inFlight[i] >= 1 { return cooldown.penalty }
                return state.inFlight[i]
            }
            let n = state.inFlight.count
            var minimum = effectiveCount(0)
            for i in 1 ..< n {
                let value = effectiveCount(i)
                if value < minimum { minimum = value }
            }
            // Rotating round-robin tie-break across all clients, not just the current candidate
            // set, so client 0 does not accumulate traffic every time the candidates narrow.
            var chosen = state.rotation
            for offset in 0 ..< n {
                let i = (state.rotation + offset) % n
                if effectiveCount(i) == minimum {
                    chosen = i
                    break
                }
            }
            state.rotation = (chosen + 1) % n
            state.inFlight[chosen] += 1
            return chosen
        }
    }

    private func release(_ index: Int) {
        state.withLock { $0.inFlight[index] -= 1 }
    }

    private func recordSuccess(_ index: Int) {
        state.withLock { $0.probationary[index] = false }
    }

    private func recordFailure(_ index: Int) {
        let until = ContinuousClock.now + cooldown.duration
        state.withLock {
            $0.cooledUntil[index] = until
            // Enter half-open probation when the cooldown eventually expires. If the probe
            // after expiry also fails, this stays true and the next cooldown resets.
            $0.probationary[index] = true
        }
    }
}
