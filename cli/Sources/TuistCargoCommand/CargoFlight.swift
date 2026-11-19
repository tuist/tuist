import Foundation
import Synchronization
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// A machine-wide claim on compiling one cache key, like Kache's flights. Builds that share the cache (worktrees,
/// agents, separate target directories) would otherwise compile the same key at once after both missed: the owner
/// holds an advisory lock on `flights/<key>` from its miss until its result is stored, and a build that finds it held
/// waits for it. Whoever holds the flight looks in the store again before compiling: a build that just stored the key
/// may have released it after this one looked. The kernel releases the lock when its holder exits, crashes included.
final class CargoFlight: Sendable {
    /// How long a build waits for another build's compilation before compiling the key itself. A holder that exits
    /// releases the flight at once, so only one that stalls (stopped, or slower than any compilation) reaches it.
    static let maximumWait: TimeInterval = 600

    /// How long this build waited for another build to release the key.
    let waited: TimeInterval
    private let path: String
    private let descriptor: Mutex<Int32>

    private init(path: String, descriptor: Int32, waited: TimeInterval) {
        self.path = path
        self.descriptor = Mutex(descriptor)
        self.waited = waited
    }

    deinit { release() }

    /// Takes the flight of `key` in the cache at `root`, waiting while another build holds it. `nil` when the wait
    /// reached its bound or the lock file could not be used: the caller compiles without a flight. Throws only
    /// `CancellationError`.
    static func join(root: URL, key: String, maximumWait: TimeInterval = maximumWait) async throws -> CargoFlight? {
        let path = root.appendingPathComponent("flights/" + key).path
        if FileManager.default.fileExists(atPath: path + unstoredSuffix) { return nil }
        let started = Date()
        do {
            if let flight = try claim(path, started: nil) { return flight }
            var nap: UInt64 = 1_000_000
            while Date().timeIntervalSince(started) < maximumWait {
                try await Task.sleep(nanoseconds: nap)
                // Learn of the holder's release within milliseconds without polling a long wait at that rate.
                nap = min(nap * 2, 20_000_000)
                if let flight = try claim(path, started: started) { return flight }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {}
        return nil
    }

    /// Marks a key whose holder released it without storing a result, such as a build script whose outputs the cache
    /// refuses: waiting for it gains nothing, so builds no longer wait for each other on it.
    func markUnstored() {
        FileManager.default.createFile(atPath: path + Self.unstoredSuffix, contents: nil)
    }

    private static let unstoredSuffix = ".unstored"

    /// Ends the claim. The file is unlinked while still locked, so a build that opened it before sees that its lock
    /// names no flight and opens the path again, rather than both owning the key.
    func release() {
        descriptor.withLock { descriptor in
            guard descriptor >= 0 else { return }
            unlink(path)
            close(descriptor)
            descriptor = -1
        }
    }

    private struct Unusable: Error {}

    /// Locks the flight at `path` without waiting, or `nil` when another process holds it.
    private static func claim(_ path: String, started: Date?) throws -> CargoFlight? {
        var descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        if descriptor < 0, errno == ENOENT {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
            )
            descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else { throw Unusable() }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(descriptor)
            if error == EWOULDBLOCK { return nil }
            throw Unusable()
        }
        // The previous owner unlinked the file it held: a lock on it claims nothing, so this counts as still busy
        // and the next attempt opens the path again.
        var held = stat()
        var named = stat()
        guard fstat(descriptor, &held) == 0, stat(path, &named) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino
        else {
            close(descriptor)
            return nil
        }
        return CargoFlight(path: path, descriptor: descriptor, waited: started.map { Date().timeIntervalSince($0) } ?? 0)
    }
}
