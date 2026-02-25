import Foundation

public enum TestingCommandLocks {
    @TaskLocal public static var xcodeBuildPoolLock: PoolLock = .init(
        capacity: xcodeBuildPoolSize()
    )
    @TaskLocal public static var installPoolLock: PoolLock = .init(
        capacity: installPoolSize()
    )

    public static func acquiringXcodeBuildPoolLock(_ closure: () async throws -> Void) async throws {
        try await withPoolLock(xcodeBuildPoolLock, closure)
    }

    public static func acquiringInstallPoolLock(_ closure: () async throws -> Void) async throws {
        try await withPoolLock(installPoolLock, closure)
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

    private static func installPoolSize() -> Int {
        guard let value = ProcessInfo.processInfo.environment["TUIST_ACCEPTANCE_INSTALL_POOL_SIZE"],
              let parsed = Int(value),
              parsed > 0
        else {
            return 2
        }
        return parsed
    }
}
