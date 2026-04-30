#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

import Foundation
import Path

public enum FileLockError: Error, CustomStringConvertible {
    case unableToOpen(path: AbsolutePath, errno: Int32)
    case unableToLock(path: AbsolutePath, errno: Int32)

    public var description: String {
        switch self {
        case let .unableToOpen(path, errno):
            return "Unable to open lock file at \(path.pathString) (errno \(errno))"
        case let .unableToLock(path, errno):
            return "Unable to acquire lock on \(path.pathString) (errno \(errno))"
        }
    }
}

/// A cross-process advisory lock backed by `flock(2)`, available on macOS and
/// Linux. The blocking acquire runs on a background queue so it does not stall
/// the cooperative thread pool. The lock is released automatically when the
/// underlying file descriptor is closed at the end of the closure.
///
/// Notes:
/// - The kernel releases `flock` advisory locks when the holding process
///   exits, so a crashed process cannot leave a stale lock on disk.
/// - The lock is advisory: only callers that take it observe mutual exclusion.
///   All readers and writers in this codebase that touch the protected file
///   must go through `FileLock`.
/// - Cancellation while waiting for the lock is not propagated: the blocking
///   `flock` call runs on a background queue and the awaiting task remains
///   suspended until acquisition succeeds.
public struct FileLock {
    private let lockPath: AbsolutePath

    public init(at lockPath: AbsolutePath) {
        self.lockPath = lockPath
    }

    public func withExclusiveLock<T>(_ body: () async throws -> T) async throws -> T {
        let fd = try await acquire()
        defer { close(fd) }
        return try await body()
    }

    private func acquire() async throws -> Int32 {
        let path = lockPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = open(path.pathString, O_RDWR | O_CREAT, 0o644)
                guard fd != -1 else {
                    continuation.resume(throwing: FileLockError.unableToOpen(path: path, errno: errno))
                    return
                }
                guard flockExclusive(fd) == 0 else {
                    let lockErrno = errno
                    close(fd)
                    continuation.resume(throwing: FileLockError.unableToLock(path: path, errno: lockErrno))
                    return
                }
                continuation.resume(returning: fd)
            }
        }
    }
}

// On Darwin, the C function `flock(2)` is shadowed in the Swift overlay by
// the `struct flock` used by `fcntl(2)` POSIX record locking, so a direct
// `flock(fd, LOCK_EX)` call fails to type-check. Resolving the symbol via
// `dlsym` disambiguates it portably across macOS and Linux without requiring
// a separate C target.
private typealias _FlockFn = @convention(c) (Int32, Int32) -> Int32
private let _flockFn: _FlockFn = {
    guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "flock") else {
        fatalError("Unable to resolve flock(2) via dlsym")
    }
    return unsafeBitCast(symbol, to: _FlockFn.self)
}()

private func flockExclusive(_ fd: Int32) -> Int32 {
    _flockFn(fd, LOCK_EX)
}
