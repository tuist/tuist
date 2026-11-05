import Synchronization

/// Keeps the writes of a client-streaming request inside the call that owns them.
///
/// grpc-swift's one-shot executor returns from the response handler, closes the HTTP/2 stream, and
/// only then cancels the request producer, without waiting for it. NIO queues a write onto the event
/// loop after releasing the writer's lock, so a write the producer had already started can land after
/// that close. The transport treats a message on a half-closed stream as unreachable, which is an
/// `assertionFailure` in debug builds and kills the process.
///
/// Run the producer's writes through `run` and call `stop` in the response handler: `stop` cancels the
/// writes (also releasing one parked on flow control) and waits for them, so every write is queued
/// before gRPC closes the stream. A producer that starts after `stop` writes nothing.
final class StreamingRequestProducer: Sendable {
    private enum State {
        case idle
        case running(Task<Void, any Error>)
        case stopped
    }

    private let state = Mutex(State.idle)

    func run(_ writes: @escaping @Sendable () async throws -> Void) async throws {
        let task: Task<Void, any Error>? = state.withLock { state in
            guard case .idle = state else { return nil }
            let task = Task { try await writes() }
            state = .running(task)
            return task
        }
        guard let task else { return }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    func stop() async {
        let task: Task<Void, any Error>? = state.withLock { state in
            defer { state = .stopped }
            guard case let .running(task) = state else { return nil }
            return task
        }
        guard let task else { return }
        task.cancel()
        _ = await task.result
    }
}
