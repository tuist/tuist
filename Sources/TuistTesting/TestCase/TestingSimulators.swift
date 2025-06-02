public enum TestingSimulators {
    @TaskLocal public static var poolLock: PoolLock = .init(capacity: 8)

    public static func acquiringLockIfNeeded(arguments: [String], _ closure: () async throws -> Void) async throws {
        if arguments.first(where: { ["-destination", "--device"].contains($0) }) != nil {
            await poolLock.acquire()
            do {
                try await closure()
            } catch {
                await poolLock.release()
                throw error
            }
            await poolLock.release()
        } else {
            try await closure()
        }
    }
}
