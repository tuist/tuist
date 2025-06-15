public enum TestingSimulators {
    @TaskLocal public static var poolLock: PoolLock = .init(capacity: 8)

    public static func acquiringPoolLock(_ closure: () async throws -> Void) async throws {
        await poolLock.acquire()
        do {
            try await closure()
        } catch {
            await poolLock.release()
            throw error
        }
        await poolLock.release()
    }
}
