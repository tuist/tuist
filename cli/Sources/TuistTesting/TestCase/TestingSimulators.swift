import Foundation

public enum TestingSimulators {
    @TaskLocal public static var simulatorPoolLock: PoolLock = .init(
        capacity: simulatorPoolSize()
    )

    public static func acquiringSimulatorPoolLock(_ closure: () async throws -> Void) async throws {
        try await withPoolLock(simulatorPoolLock, closure)
    }

    /// Backward-compatible alias.
    public static func acquiringPoolLock(_ closure: () async throws -> Void) async throws {
        try await acquiringSimulatorPoolLock(closure)
    }

    private static func withPoolLock(
        _ lock: PoolLock,
        _ closure: () async throws -> Void
    ) async throws {
        await lock.acquire()
        do {
            try await closure()
        } catch {
            await lock.release()
            throw error
        }
        await lock.release()
    }

    private static func simulatorPoolSize() -> Int {
        guard let value = ProcessInfo.processInfo.environment["TUIST_ACCEPTANCE_SIMULATOR_POOL_SIZE"],
              let parsed = Int(value),
              parsed > 0
        else {
            return 2
        }
        return parsed
    }
}
