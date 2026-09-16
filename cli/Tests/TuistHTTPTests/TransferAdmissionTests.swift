import Foundation
import Synchronization
import Testing

@testable import TuistHTTP

struct TransferAdmissionTests {
    private final class Gauge: Sendable {
        private let state = Mutex((current: 0, peak: 0))

        func enter() {
            state.withLock {
                $0.current += 1
                $0.peak = max($0.peak, $0.current)
            }
        }

        func leave() {
            state.withLock { $0.current -= 1 }
        }

        var peak: Int { state.withLock { $0.peak } }
    }

    @Test func runs_no_more_transfers_at_once_than_its_limit() async throws {
        let subject = TransferAdmission(limit: 3)
        let gauge = Gauge()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 20 {
                group.addTask {
                    try await subject.run {
                        gauge.enter()
                        try await Task.sleep(for: .milliseconds(5))
                        gauge.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(gauge.peak == 3)
    }

    @Test func a_transfer_that_throws_hands_its_slot_on() async throws {
        let subject = TransferAdmission(limit: 1)

        await #expect(throws: URLError.self) {
            try await subject.run { throw URLError(.timedOut) }
        }

        #expect(try await subject.run { 42 } == 42)
    }

    @Test func a_cancelled_waiter_leaves_without_taking_a_slot() async throws {
        let subject = TransferAdmission(limit: 1)
        let holderStarted = AsyncStream<Void>.makeStream()
        let releaseHolder = AsyncStream<Void>.makeStream()

        let holder = Task {
            try await subject.run {
                holderStarted.continuation.yield()
                for await _ in releaseHolder.stream {
                    break
                }
            }
        }
        for await _ in holderStarted.stream {
            break
        }

        let waiter = Task { try await subject.run { "admitted" } }
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }

        releaseHolder.continuation.yield()
        try await holder.value
        #expect(try await subject.run { "next" } == "next")
    }
}
