import Darwin
import Foundation
import TuistEnvironment

/// A disposable, four-way cache: 512 slots bound retained bytes to one
/// gibibyte. Atomic replacement and digest checks turn races into cache misses.
struct LocalChunkCache: Sendable {
    static var moduleDirectory: URL {
        URL(fileURLWithPath: Environment.current.cacheDirectory.appending(component: "module-download-chunks-v1").pathString)
    }

    let directory: URL
    let scope: String

    func path(for digest: ContentDefinedChunking.Digest) -> URL {
        paths(for: digest)[0]
    }

    private func paths(for digest: ContentDefinedChunking.Digest) -> [URL] {
        let key = ContentDefinedChunking.digest(Data("\(scope)\0\(digest.hash)\0\(digest.size)".utf8)).hash
        let bucket = (Int(key.prefix(4), radix: 16) ?? 0) % 128
        return (0 ..< 4).map { directory.appendingPathComponent(String(format: "%02x-%d", bucket, $0)) }
    }

    func get(_ digest: ContentDefinedChunking.Digest) -> Data? {
        guard (1 ... ContentDefinedChunking.maximumBytes).contains(digest.size) else { return nil }
        for path in paths(for: digest) {
            guard let input = try? FileHandle(forReadingFrom: path) else { continue }
            defer { try? input.close() }
            guard let bytes = try? input.read(upToCount: digest.size + 1),
                  ContentDefinedChunking.digest(bytes) == digest else { continue }
            return bytes
        }
        return nil
    }

    func put(_ digest: ContentDefinedChunking.Digest, bytes: Data) {
        guard (1 ... ContentDefinedChunking.maximumBytes).contains(bytes.count),
              ContentDefinedChunking.digest(bytes) == digest else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else { return }
            defer { flock(descriptor, LOCK_UN) }
            if get(digest) != nil { return }
            let destination = paths(for: digest).min {
                let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ??
                    .distantPast
                let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ??
                    .distantPast
                return first < second
            } ?? path(for: digest)
            let pending = directory.appendingPathComponent(".pending")
            try bytes.write(to: pending)
            if rename(pending.path, destination.path) != 0 { try? FileManager.default.removeItem(at: pending) }
        } catch { /* Disk-cache failures do not prevent a remote restore. */ }
    }
}
