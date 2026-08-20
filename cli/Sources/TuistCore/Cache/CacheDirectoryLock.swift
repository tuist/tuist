import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistLogging

/// Coordinates access to the global cache directories between the Tuist processes running on one
/// host.
///
/// The directories under the cache root are shared, and `tuist clean` empties them, so a command
/// that reads or writes one while a clean deletes it observes a path that disappeared underneath
/// it. Commands that use a cache take shared access and still run concurrently with each other;
/// a clean takes exclusive access, so it waits for them and they wait for it.
///
/// Access is advisory and held through an open descriptor, which the kernel closes when the
/// process exits. A command killed mid-run therefore cannot wedge the next one, and no cleanup
/// pass has to reason about locks left behind by a crash.
///
/// Only short bursts of cache work belong inside these calls. Access that lasts as long as the
/// command does, such as a test run writing its result bundle under `Runs`, would leave a clean
/// waiting for minutes, which is worse than the interleaving it prevents.
///
/// These calls do not nest. Each one opens its own descriptor, so a second request for the same
/// category from inside the first waits on a lock this process is already holding and never
/// returns. Take access around the work that touches the directory, not around a span that may
/// reach back into the cache.
public protocol CacheDirectoryLocking: Sendable {
    /// Runs `body` while this process is using `category`, alongside other users of it.
    func whileUsing<T>(_ category: CacheCategory, _ body: () async throws -> T) async throws -> T

    /// Runs `body` while this process is the only one touching `category`.
    func whileEmptying<T>(_ category: CacheCategory, _ body: () async throws -> T) async throws -> T
}

public struct CacheDirectoryLock: CacheDirectoryLocking {
    private let cacheDirectory: AbsolutePath?
    private let fileSystem: FileSysteming

    /// - Parameter cacheDirectory: The cache root to place lock files under. Defaults to the
    ///   environment's, which is what every command uses; tests pass their own so a unit test
    ///   never takes a lock the machine's other Tuist processes wait on.
    public init(
        cacheDirectory: AbsolutePath? = nil,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.cacheDirectory = cacheDirectory
        self.fileSystem = fileSystem
    }

    public func whileUsing<T>(_ category: CacheCategory, _ body: () async throws -> T) async throws -> T {
        try await withAccess(to: category, mode: LOCK_SH, body)
    }

    public func whileEmptying<T>(_ category: CacheCategory, _ body: () async throws -> T) async throws -> T {
        try await withAccess(to: category, mode: LOCK_EX, body)
    }

    /// Falls back to running `body` unguarded when the lock cannot be taken, because a cache that
    /// cannot be coordinated is still a cache. Refusing to run would turn an unwritable lock
    /// directory into a failure of every command, which is a worse outcome than the interleaving
    /// the lock exists to prevent.
    private func withAccess<T>(
        to category: CacheCategory,
        mode: Int32,
        _ body: () async throws -> T
    ) async throws -> T {
        guard let descriptor = await descriptor(for: category, mode: mode) else {
            return try await body()
        }
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try await body()
    }

    /// `flock` blocks until the lock is granted, so it is taken off the cooperative pool: a
    /// command waiting on a clean must not consume a thread other work is scheduled on.
    private func descriptor(for category: CacheCategory, mode: Int32) async -> Int32? {
        let lockPath: AbsolutePath
        do {
            lockPath = try await lockFile(for: category)
        } catch {
            Logger.current.debug("Couldn't prepare the \(category.rawValue) cache lock: \(error)")
            return nil
        }
        let descriptor = await Task.detached {
            let descriptor = open(lockPath.pathString, O_CREAT | O_RDWR, 0o644)
            guard descriptor >= 0 else { return Int32?.none }
            guard flock(descriptor, mode) == 0 else {
                close(descriptor)
                return Int32?.none
            }
            return descriptor
        }.value
        if descriptor == nil {
            Logger.current.debug("Couldn't take the \(category.rawValue) cache lock at \(lockPath.pathString)")
        }
        return descriptor
    }

    /// Lock files sit beside the directories they guard rather than inside them, so that emptying
    /// a category leaves its lock in place. A lock file removed by the clean it coordinates would
    /// hand the next two processes separate files, and each would hold what it takes to be the
    /// same lock.
    private func lockFile(for category: CacheCategory) async throws -> AbsolutePath {
        let root = cacheDirectory ?? Environment.current.cacheDirectory
        let directory = root.appending(component: "Locks")
        try await fileSystem.makeDirectory(at: directory, options: [.createTargetParentDirectories])
        return directory.appending(component: "\(category.directoryName).lock")
    }
}
