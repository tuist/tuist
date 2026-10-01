import Foundation
import Testing
@testable import TuistREAPI

struct LeastOutstandingSelectorTests {
    private final class FakeClient: Sendable { let id: Int; init(_ id: Int) { self.id = id } }

    @Test func picksLeastOutstandingClient() async throws {
        let selector = LeastOutstandingSelector((0 ..< 4).map(FakeClient.init))
        let release = AsyncStream<Void>.makeStream()
        // Occupy two clients concurrently. Which two Task scheduling lands them on is
        // non-deterministic, so the test checks the picker's contract (new picks avoid
        // every busy client) rather than specific IDs.
        let occupied = (0 ..< 2).map { _ in
            Task {
                try await selector.withClient { _ in
                    for await _ in release.stream { break }
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
        // The two free clients are both reachable (round-robin alternates between them).
        #expect(picks.count == 2)
        release.continuation.finish()
        for task in occupied { _ = try? await task.value }
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
}
