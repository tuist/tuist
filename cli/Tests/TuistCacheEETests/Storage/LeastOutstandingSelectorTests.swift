import Foundation
import Testing
@testable import TuistREAPI

struct LeastOutstandingSelectorTests {
    private final class FakeClient: Sendable { let id: Int; init(_ id: Int) { self.id = id } }

    @Test func picksLeastOutstandingClient() async throws {
        let selector = LeastOutstandingSelector((0 ..< 4).map(FakeClient.init))
        // Separate stream per occupied task so no two tasks iterate the same (unicast)
        // AsyncStream, which would trap at runtime.
        let gates = (0 ..< 2).map { _ in AsyncStream<Void>.makeStream() }
        let occupied = gates.map { gate in
            Task {
                try await selector.withClient { _ in
                    for await _ in gate.stream {
                        break
                    }
                }
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        let busy = Set(selector.inFlight.enumerated().filter { $0.element > 0 }.map(\.offset))
        #expect(busy.count == 2)
        var picks = Set<Int>()
        for _ in 0 ..< 4 {
            try await selector.withClient { client in picks.insert(client.id) }
        }
        #expect(picks.isDisjoint(with: busy))
        // The two free clients are both reachable (tie-break alternates between them).
        #expect(picks.count == 2)
        for gate in gates {
            gate.continuation.finish()
        }
        for task in occupied {
            _ = try? await task.value
        }
    }

    @Test func releasesReservationOnThrow() async throws {
        let selector = LeastOutstandingSelector((0 ..< 4).map(FakeClient.init))
        struct Boom: Error {}
        for _ in 0 ..< 3 {
            await #expect(throws: Boom.self) {
                try await selector.withClient { _ in throw Boom() }
            }
        }
        #expect(selector.inFlight == [0, 0, 0, 0])
    }

    @Test func releasesReservationOnCancellation() async throws {
        let selector = LeastOutstandingSelector((0 ..< 2).map(FakeClient.init))
        let task = Task {
            try await selector.withClient { _ in
                try await Task.sleep(for: .seconds(10))
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        _ = try? await task.value
        #expect(selector.inFlight == [0, 0])
    }

    @Test func cooldownAvoidsAFailedClientOnTheNextPick() async throws {
        let selector = LeastOutstandingSelector((0 ..< 4).map(FakeClient.init))
        // Fail the first attempt in a way `shouldPenalize` opts into. The failed index must
        // not be the one the retry lands on, otherwise a wedged connection keeps collecting
        // the retries whose predecessor it just killed.
        struct Wedged: Error {}
        var failedIndex: Int?
        try? await selector.withClient(shouldPenalize: { _ in true }) { client in
            failedIndex = client.id
            throw Wedged()
        }
        let failed = try #require(failedIndex)
        for _ in 0 ..< 8 {
            try await selector.withClient { client in
                #expect(client.id != failed)
            }
        }
    }

    @Test func cooldownExpiresAndClientBecomesEligibleAgain() async throws {
        var cooldown = LeastOutstandingSelector<FakeClient>.Cooldown.default
        cooldown.duration = .milliseconds(50)
        let selector = LeastOutstandingSelector((0 ..< 2).map(FakeClient.init), cooldown: cooldown)
        struct Wedged: Error {}
        var failedIndex: Int?
        try? await selector.withClient(shouldPenalize: { _ in true }) { client in
            failedIndex = client.id
            throw Wedged()
        }
        let failed = try #require(failedIndex)
        try await Task.sleep(for: .milliseconds(100))
        // After the cooldown expires, the previously-failed client is picked again when it
        // is the least-outstanding: nothing is permanent.
        var picks = Set<Int>()
        for _ in 0 ..< 4 {
            try await selector.withClient { client in picks.insert(client.id) }
        }
        #expect(picks.contains(failed))
    }

    @Test func rotatingTieBreakSpreadsLoadInsteadOfFavoringLowIndices() async throws {
        let selector = LeastOutstandingSelector((0 ..< 4).map(FakeClient.init))
        var histogram = [0, 0, 0, 0]
        for _ in 0 ..< 20 {
            try await selector.withClient { client in histogram[client.id] += 1 }
        }
        // Every client receives traffic; the rotation runs through all of them before coming
        // back to index 0. A fixed-start tie-break would send every call to client 0.
        #expect(histogram.allSatisfy { $0 > 0 })
    }
}
