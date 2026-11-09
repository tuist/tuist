import Synchronization
import TestCoverageAttribution
import Testing
@testable import TuistREAPI

@Suite(.coverageAttribution)
struct StreamingRequestProducerTests {
    @Test func stopWaitsForParkedWritesToEnd() async throws {
        let producer = StreamingRequestProducer()
        let ended = Atomic(false)
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let run = Task {
            try await producer.run {
                defer { ended.store(true, ordering: .sequentiallyConsistent) }
                startedContinuation.yield()
                try await Task.sleep(for: .seconds(3600))
            }
        }
        for await _ in started {
            break
        }

        await producer.stop()

        let endedBeforeStopReturned = ended.load(ordering: .sequentiallyConsistent)
        #expect(endedBeforeStopReturned)
        await #expect(throws: CancellationError.self) { try await run.value }
    }

    @Test func producerStartingAfterStopWritesNothing() async throws {
        let producer = StreamingRequestProducer()
        let wrote = Atomic(false)

        await producer.stop()
        try await producer.run { wrote.store(true, ordering: .sequentiallyConsistent) }

        let didWrite = wrote.load(ordering: .sequentiallyConsistent)
        #expect(!didWrite)
    }

    @Test func cancellingTheCallCancelsTheWrites() async throws {
        let producer = StreamingRequestProducer()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let run = Task {
            try await producer.run {
                startedContinuation.yield()
                try await Task.sleep(for: .seconds(3600))
            }
        }
        for await _ in started {
            break
        }

        run.cancel()

        await #expect(throws: CancellationError.self) { try await run.value }
    }
}
