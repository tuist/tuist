import Foundation
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

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
    /// Streams the handle's contents until end of file, reading on a dedicated thread.
    ///
    /// This deliberately avoids `readabilityHandler`: on Linux, when a short-lived child writes its output and exits
    /// right away, the readability source can deliver the data but never the end of file, so the stream stays open
    /// after the process is gone and the caller waits forever.
    func byteStream() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let fileDescriptor = FileDescriptor(rawValue: fileDescriptor)
            let thread = Thread {
                withExtendedLifetime(self) {
                    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                    while true {
                        do {
                            let count = try buffer.withUnsafeMutableBytes {
                                try fileDescriptor.read(into: $0, retryOnInterrupt: true)
                            }
                            if count == 0 {
                                continuation.finish()
                                return
                            }
                            continuation.yield(Data(buffer[0 ..< count]))
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                }
            }
            thread.name = "dev.tuist.process-output"
            thread.start()
        }
    }
}
