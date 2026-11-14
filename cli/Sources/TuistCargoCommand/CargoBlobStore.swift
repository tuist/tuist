import Foundation
import Synchronization
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// The content-addressed files every Cargo cache layer keeps under `<root>/blobs/<hash>`. Blobs carry the time they
/// were last stored or used, never their source's: build scripts copy files out of crate archives with years-old
/// timestamps, which the cache's age-based pruning would evict.
struct CargoBlobStore {
    let root: URL

    /// Digests of files this process published, by the identity each source had when it was hashed. Hooks are
    /// served in the process that collects dependency units after the build, so a unit's rlib that per-crate
    /// publication stored is not copied and hashed a second time.
    private static let published = Published()

    /// Writes an index or record file atomically, creating its directory. Unlike Foundation's `Data.write`, it does not
    /// `fsync`: a seed build writes a record for every blob and compilation, and their flushes slowed every rustc
    /// running beside them. Readers verify or decode what they read, so a write a crash loses is only a miss.
    static func write(_ data: Data, to file: URL) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString).tmp").path
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temporary, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            unlink(temporary)
            throw error
        }
    }

    func path(_ digest: REAPI.Digest) -> URL {
        root.appendingPathComponent("blobs/" + digest.hash, isDirectory: false)
    }

    /// Whether a regular file of the digest's size is stored. Readers verify the content they take.
    func contains(_ digest: REAPI.Digest) -> Bool {
        var value = stat()
        return lstat(path(digest).path, &value) == 0 && value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            && Int64(value.st_size) == digest.sizeBytes
    }

    /// Copies `file` into the store (a clone on APFS) and hashes the copy once, so the digest describes exactly the
    /// bytes stored even if the source changes meanwhile. A blob already stored is kept and its use renewed.
    @discardableResult
    func publish(_ file: URL, expecting expected: REAPI.Digest? = nil) throws -> REAPI.Digest {
        let source = try? CargoInputHasher.identity(file)
        if let source, source.precise, let digest = Self.published.digest(file.path, source),
           expected.map({ $0 == digest }) ?? true, contains(digest)
        {
            markUsed(digest)
            return digest
        }
        let blobs = root.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        let temporary = blobs.appendingPathComponent(".tmp-" + UUID().uuidString, isDirectory: false)
        try FileManager.default.copyItem(at: file, to: temporary)
        do {
            let digest = try REAPI.digest(file: temporary)
            if let expected, digest != expected { throw REAPICacheError.corruptBlob }
            if let source, source.precise, (try? CargoInputHasher.identity(file)) == source {
                Self.published.set(file.path, source, digest)
            }
            if contains(digest) {
                unlink(temporary.path)
                markUsed(digest)
                return digest
            }
            let destination = path(digest)
            // A clone keeps the source's times; `rename` replaces any partial blob atomically.
            guard utimes(temporary.path, nil) == 0, rename(temporary.path, destination.path) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            // The blob was just hashed: restoration verifies it through this record instead of hashing it again.
            CargoInputHasher(sessionDirectory: root.appendingPathComponent("verified")).remember(destination, digest: digest)
            return digest
        } catch {
            unlink(temporary.path)
            throw error
        }
    }

    /// Renews the blob's use mark when it is more than an hour old. Returns whether it was renewed, which changes the
    /// identity its verified digest is recorded with.
    @discardableResult
    func markUsed(_ digest: REAPI.Digest) -> Bool { Self.markUsed(path(digest).path) }

    /// `stat`, not Foundation's attributes, which also read extended attributes.
    @discardableResult
    static func markUsed(_ path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        #if os(Linux)
            let modified = info.st_mtim.tv_sec
        #else
            let modified = info.st_mtimespec.tv_sec
        #endif
        guard Date().timeIntervalSince1970 - Double(modified) > 3600 else { return false }
        return utimes(path, nil) == 0
    }

    private final class Published: Sendable {
        private let digests = Mutex<[String: (CargoInputHasher.Identity, REAPI.Digest)]>([:])

        func digest(_ path: String, _ identity: CargoInputHasher.Identity) -> REAPI.Digest? {
            digests.withLock { $0[path].flatMap { $0.0 == identity ? $0.1 : nil } }
        }

        func set(_ path: String, _ identity: CargoInputHasher.Identity, _ digest: REAPI.Digest) {
            digests.withLock { $0[path] = (identity, digest) }
        }
    }
}
