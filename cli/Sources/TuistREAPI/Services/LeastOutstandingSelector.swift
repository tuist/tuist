import Foundation
import Synchronization

/// Routes each call to whichever client currently holds the fewest in-flight RPCs,
/// so a connection that stalls (or whose peer has gone silent) stops collecting new
/// work until it drains. Ties break round-robin to spread load evenly when every
/// client is idle.
///
/// Scoped via `withClient`: the in-flight counter increments on checkout and
/// decrements in `defer`, so throw and cancel paths cannot let counts drift.
final class LeastOutstandingSelector<Client: Sendable>: Sendable {
    private struct State {
        var inFlight: [Int]
        var nextTieBreak: Int
    }

    let clients: [Client]
    private let state: Mutex<State>

    init(_ clients: [Client]) {
        precondition(!clients.isEmpty, "LeastOutstandingSelector requires at least one client")
        self.clients = clients
        state = Mutex(State(inFlight: Array(repeating: 0, count: clients.count), nextTieBreak: 0))
    }

    /// Reserves a client, runs `operation` with it, and releases the reservation when
    /// the operation returns, throws, or is cancelled. The in-flight count is a
    /// point-in-time snapshot taken at reservation time, not a lock, so two
    /// concurrent reservations can land on the same client when they both see the
    /// minimum.
    func withClient<T: Sendable>(_ operation: (Client) async throws -> T) async rethrows -> T {
        let index = state.withLock { state -> Int in
            var minimum = state.inFlight[0]
            for count in state.inFlight.dropFirst() where count < minimum { minimum = count }
            var candidates: [Int] = []
            candidates.reserveCapacity(state.inFlight.count)
            for (position, count) in state.inFlight.enumerated() where count == minimum {
                candidates.append(position)
            }
            let chosen = candidates[state.nextTieBreak % candidates.count]
            state.nextTieBreak = (state.nextTieBreak + 1) % candidates.count
            state.inFlight[chosen] += 1
            return chosen
        }
        defer { state.withLock { $0.inFlight[index] -= 1 } }
        return try await operation(clients[index])
    }

    /// Snapshot of in-flight counts, for tests and observability.
    var inFlight: [Int] { state.withLock { $0.inFlight } }
}
