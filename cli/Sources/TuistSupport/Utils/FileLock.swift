import Darwin
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

/// A cross-process advisory lock backed by `flock(2)`.
///
/// `withExclusiveLock` blocks until the lock is acquired and releases it when
/// the closure returns. The blocking `flock(2)` call is performed on a
/// background queue so it does not stall the cooperative thread pool.
public struct FileLock {
    private let lockPath: AbsolutePath

    public init(at lockPath: AbsolutePath) {
        self.lockPath = lockPath
    }

    public func withExclusiveLock<T>(_ body: () async throws -> T) async throws -> T {
        let fd = try await acquire()
        defer { Darwin.close(fd) }
        return try await body()
    }

    private func acquire() async throws -> Int32 {
        let path = lockPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fd = Darwin.open(path.pathString, O_RDWR | O_CREAT, 0o644)
                guard fd != -1 else {
                    continuation.resume(throwing: FileLockError.unableToOpen(path: path, errno: errno))
                    return
                }
                guard flockExclusive(fd) == 0 else {
                    Darwin.close(fd)
                    continuation.resume(throwing: FileLockError.unableToLock(path: path, errno: errno))
                    return
                }
                continuation.resume(returning: fd)
            }
        }
    }
}

// `Darwin.flock` (the C function) is shadowed by `Darwin.flock` (the struct
// used by `fcntl` POSIX locking). Resolve it dynamically via `dlsym` so the
// compiler can pick the function unambiguously.
private typealias _FlockFn = @convention(c) (Int32, Int32) -> Int32
private let _flockFn: _FlockFn = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "flock") else {
        fatalError("Unable to resolve flock(2) via dlsym")
    }
    return unsafeBitCast(symbol, to: _FlockFn.self)
}()

private func flockExclusive(_ fd: Int32) -> Int32 {
    _flockFn(fd, LOCK_EX)
}
