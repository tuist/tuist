import Foundation

/// Runs an `action` that is cancelled after the given `timeout`. When the `timeout` elapses, `onTimeout` callback is called.
/// Inspired by: https://alejandromp.com/development/blog/the-importance-of-cooperative-cancellation/
public func withTimeout(
    _ timeout: Duration,
    onTimeout: @escaping () throws -> Void,
    action: @escaping () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await action()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            try onTimeout()
        }
        try await group.next()
        group.cancelAll()
    }
}
