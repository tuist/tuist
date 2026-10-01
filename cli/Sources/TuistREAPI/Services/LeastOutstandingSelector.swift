import Foundation
import Synchronization

/// Routes each call to whichever client currently holds the fewest in-flight RPCs, with a
/// cooldown penalty on clients whose last RPC failed in a way that suggests the underlying
/// connection, not the request, is at fault.
///
/// Round-robin selection sends a retry back to a wedged connection as soon as its failed RPC
/// drops out of flight: the dead client reaches 0 before everyone else, becomes the unique
/// minimum, and attracts the retry. The failure-aware picker inflates such a client's effective
/// in-flight count for the cooldown window so retries land somewhere else first, giving
/// keepalive time to tear the socket down.
///
/// Scoped via `withClient`: the in-flight counter decrements in `defer` so throw and cancel
/// paths release it too; a thrown error the caller says should penalize the connection records
/// a cooldown on that client's index.
final class LeastOutstandingSelector<Client: Sendable>: Sendable {
    struct Cooldown: Sendable {
        /// How long a client is treated as unhealthy after a connection-shaped failure. Long
        /// enough that keepalive's `time + timeout` window has had a chance to kill a silently
        /// dead peer, so the next attempt lands on a client whose socket is still live.
        var duration: Duration = .seconds(45)

        /// Virtual in-flight inflation applied to a cooled client's effective count. Big enough
        /// to dominate any realistic in-flight count across a transfer concurrency of 32, so a
        /// cooled client is never picked while a healthy one is available.
        var penalty: Int = 1_000_000

        static var `default`: Cooldown { Cooldown() }
    }

    private struct State {
        var inFlight: [Int]
        var cooledUntil: [ContinuousClock.Instant?]
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
            rotation: 0
        ))
    }

    /// Reserves a client, runs `operation` with it, and releases the reservation when the
    /// operation returns, throws, or is cancelled. `shouldPenalize(error)` opts a specific
    /// error class into cooldown, so a `.notFound` or `.permissionDenied` does not get the
    /// same treatment as `.deadlineExceeded` or `.unavailable`.
    func withClient<T: Sendable>(
        shouldPenalize: @Sendable (any Error) -> Bool = { _ in false },
        _ operation: (Client) async throws -> T
    ) async throws -> T {
        let index = reserve()
        defer { release(index) }
        do {
            return try await operation(clients[index])
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
                let penalty = state.cooledUntil[i].map { now < $0 ? cooldown.penalty : 0 } ?? 0
                return state.inFlight[i] + penalty
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

    private func recordFailure(_ index: Int) {
        let until = ContinuousClock.now + cooldown.duration
        state.withLock { $0.cooledUntil[index] = until }
    }
}
