import Foundation

public enum TestingSimulators {
    @TaskLocal public static var simulatorPoolLock: PoolLock = .init(
        capacity: capacity(from: "TUIST_ACCEPTANCE_SIMULATOR_POOL_SIZE", default: 2)
    )
    @TaskLocal public static var xcodeBuildPoolLock: PoolLock = .init(
        capacity: capacity(
            from: "TUIST_ACCEPTANCE_XCODEBUILD_POOL_SIZE",
            default: max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
        )
    )
    @TaskLocal public static var installPoolLock: PoolLock = .init(
        capacity: capacity(from: "TUIST_ACCEPTANCE_INSTALL_POOL_SIZE", default: 2)
    )

    public static func acquiringSimulatorPoolLock(_ closure: () async throws -> Void) async throws {
        try await withPoolLock(simulatorPoolLock, closure)
    }

    public static func acquiringXcodeBuildPoolLock(_ closure: () async throws -> Void) async throws {
        try await withPoolLock(xcodeBuildPoolLock, closure)
    }

    public static func acquiringInstallPoolLock(_ closure: () async throws -> Void) async throws {
        try await withPoolLock(installPoolLock, closure)
    }

    // Backward-compatible alias.
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

    private static func capacity(from envVar: String, default defaultValue: Int) -> Int {
        guard
            let value = ProcessInfo.processInfo.environment[envVar],
            let parsed = Int(value),
            parsed > 0
        else {
            return defaultValue
        }
        return parsed
    }
}
