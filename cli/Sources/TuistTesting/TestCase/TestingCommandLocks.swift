import Foundation

public enum TestingCommandLocks {
    @TaskLocal public static var xcodeBuildPoolLock: PoolLock = .init(
        capacity: xcodeBuildPoolSize()
    )

    public static func acquiringXcodeBuildPoolLock(_ closure: () async throws -> Void) async throws {
        try await withPoolLock(xcodeBuildPoolLock, closure)
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

    private static func xcodeBuildPoolSize() -> Int {
        guard let value = ProcessInfo.processInfo.environment["TUIST_ACCEPTANCE_XCODEBUILD_POOL_SIZE"],
              let parsed = Int(value),
              parsed > 0
        else {
            return max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
        }
        return parsed
    }
}
