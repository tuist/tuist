import Foundation

/// Runs at most `limit` transfers at a time and parks the rest in arrival order. A parked transfer
/// has no `URLSession` task yet, so its timeouts do not run while it waits.
public final class TransferAdmission: @unchecked Sendable {
    /// Admits the downloads made on `URLSession.tuistArtifactDownload`.
    public static let artifactDownloads = TransferAdmission(
        limit: tuistURLSessionConfiguration().httpMaximumConnectionsPerHost
    )

    private let limit: Int
    private let lock = NSLock()
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public func run<T>(_ operation: () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enqueue(id: id, continuation: continuation)
            }
        } onCancel: {
            cancel(id: id)
        }
    }

    private enum Admission {
        case admitted, parked, cancelled
    }

    private func enqueue(id: UUID, continuation: CheckedContinuation<Void, any Error>) {
        let admission: Admission = lock.withLock {
            if Task.isCancelled { return .cancelled }
            if running < limit {
                running += 1
                return .admitted
            }
            waiters.append((id, continuation))
            return .parked
        }
        switch admission {
        case .admitted: continuation.resume()
        case .cancelled: continuation.resume(throwing: CancellationError())
        case .parked: break
        }
    }

    private func cancel(id: UUID) {
        let waiter: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
            return waiters.remove(at: index).continuation
        }
        waiter?.resume(throwing: CancellationError())
    }

    private func release() {
        let next: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard !waiters.isEmpty else {
                running -= 1
                return nil
            }
            return waiters.removeFirst().continuation
        }
        next?.resume()
    }
}
