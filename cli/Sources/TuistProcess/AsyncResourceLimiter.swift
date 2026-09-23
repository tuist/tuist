import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

actor AsyncResourceLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limitProvider: @Sendable () -> Int
    private var limit: Int
    private var activePermits = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.init(limitProvider: { limit })
    }

    init(limitProvider: @escaping @Sendable () -> Int) {
        let limit = limitProvider()
        precondition(limit > 0, "The process limit must be greater than zero.")
        self.limitProvider = limitProvider
        self.limit = limit
    }

    func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        refreshLimit()

        if activePermits < limit, waiters.isEmpty {
            activePermits += 1
            return
        }

        let waiterID = UUID()
        let wasGrantedPermit = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(Waiter(id: waiterID, continuation: continuation))
                grantAvailablePermits()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        }

        guard wasGrantedPermit else { throw CancellationError() }
    }

    private func release() {
        refreshLimit()
        activePermits -= 1
        grantAvailablePermits()
    }

    private func refreshLimit() {
        limit = limitProvider()
    }

    private func grantAvailablePermits() {
        while activePermits < limit, !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            activePermits += 1
            waiter.continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}

func systemMaximumConcurrentProcesses() -> Int {
    #if os(Windows)
        return CommandRunner.fallbackMaximumConcurrentProcesses
    #else
        var resourceLimit = rlimit()
        #if canImport(Glibc)
            let openFilesResource = Int32(RLIMIT_NOFILE.rawValue)
        #else
            let openFilesResource = RLIMIT_NOFILE
        #endif
        guard getrlimit(openFilesResource, &resourceLimit) == 0 else {
            return CommandRunner.fallbackMaximumConcurrentProcesses
        }
        let availableDescriptors = max(1, Int(clamping: resourceLimit.rlim_cur) - CommandRunner.reservedFileDescriptors)
        return min(
            CommandRunner.maximumConcurrentProcesses,
            max(1, availableDescriptors / CommandRunner.fileDescriptorsPerProcess)
        )
    #endif
}

extension FileHandle {
    func byteStream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    continuation.finish()
                    handle.readabilityHandler = nil
                } else {
                    continuation.yield(data)
                }
            }

            continuation.onTermination = { @Sendable _ in
                self.readabilityHandler = nil
            }
        }
    }
}
