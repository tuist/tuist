import Foundation
import Synchronization

/// Apps advance the session when changing profiles. Existing CLI consumers keep the unscoped session.
public final class ServerAuthenticationSession: Sendable {
    @TaskLocal public static var current = ServerAuthenticationSession()
    @TaskLocal public static var expectedID: UUID?
    private struct State {
        var identifier: UUID?
        var refreshes = 0
        var pendingAdvance: CheckedContinuation<Void, Never>?

        func validate(_ expected: UUID?) throws {
            guard identifier == expected else { throw CancellationError() }
        }
    }

    private let state = Mutex(State())

    public init() {}

    public var id: UUID? { state.withLock { $0.identifier } }

    public func advance() {
        state.withLock { $0.identifier = UUID() }
    }

    /// A refresh may already have rotated its server grant. Save its response before archiving the outgoing profile.
    public func advanceAfterRefreshing() async {
        await withCheckedContinuation { continuation in
            state.withLock { state in
                if state.refreshes == 0 {
                    state.identifier = UUID()
                    continuation.resume()
                } else {
                    state.pendingAdvance = continuation
                }
            }
        }
    }

    func withRefresh<T>(id: UUID?, _ action: () async throws -> T) async throws -> T {
        try state.withLock { state in
            try state.validate(id)
            guard state.pendingAdvance == nil else { throw CancellationError() }
            state.refreshes += 1
        }
        defer {
            state.withLock { state in
                state.refreshes -= 1
                if state.refreshes == 0, let continuation = state.pendingAdvance {
                    state.pendingAdvance = nil
                    state.identifier = UUID()
                    continuation.resume()
                }
            }
        }
        return try await action()
    }

    func validate(_ expected: UUID?) throws {
        try state.withLock {
            try $0.validate(expected)
        }
    }

    func withCredentialWrite<T>(_ action: () throws -> T) throws -> T {
        try state.withLock {
            if let expected = Self.expectedID { try $0.validate(expected) }
            return try action()
        }
    }
}
