import Foundation
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Shares verified file digests across the before/after checks of one compiler invocation, never across sessions.
final class CargoInputHasher {
    struct Identity: Equatable {
        let fields: [String]
        let precise: Bool
    }

    private let identify: (URL) throws -> Identity
    private let hashFile: (URL) throws -> REAPI.Digest
    private var entries: [URL: (Identity, REAPI.Digest)] = [:]
    private var supportedSources: Set<REAPI.Digest> = []

    init(
        identify: @escaping (URL) throws -> Identity = CargoInputHasher.identity,
        hashFile: @escaping (URL) throws -> REAPI.Digest = REAPI.digest(file:)
    ) {
        self.identify = identify
        self.hashFile = hashFile
    }

    func digest(_ file: URL) throws -> REAPI.Digest {
        let before = try identify(file)
        if before.precise, let (identity, digest) = entries[file], identity == before { return digest }
        let digest = try hashFile(file)
        guard try identify(file) == before else { throw CargoCacheInvocation.CacheError.unsupported }
        if before.precise { entries[file] = (before, digest) }
        return digest
    }

    /// Admission is attached to the exact bytes in the key, not a second, independently read version of the source.
    func sourceDigest(_ file: URL, validate: (Data) throws -> Void) throws -> REAPI.Digest {
        let before = try identify(file)
        if before.precise, let (identity, digest) = entries[file], identity == before, supportedSources.contains(digest) {
            return digest
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 2_000_001) ?? Data()
        guard data.count <= 2_000_000, try handle.seekToEnd() == UInt64(data.count), try identify(file) == before else {
            throw CargoCacheInvocation.CacheError.unsupported
        }
        let digest = REAPI.digest(data)
        if !supportedSources.contains(digest) {
            try validate(data)
            supportedSources.insert(digest)
        }
        if before.precise { entries[file] = (before, digest) }
        return digest
    }

    private static func identity(_ file: URL) throws -> Identity {
        var value = stat()
        guard lstat(file.path, &value) == 0, value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CargoCacheInvocation.CacheError.unsupported
        }
        #if os(Linux)
            let modified = value.st_mtim
            let changed = value.st_ctim
        #else
            let modified = value.st_mtimespec
            let changed = value.st_ctimespec
        #endif
        return Identity(
            fields: [
                String(value.st_dev), String(value.st_ino), String(value.st_size), String(value.st_mode),
                String(modified.tv_sec), String(modified.tv_nsec), String(changed.tv_sec), String(changed.tv_nsec),
            ],
            precise: changed.tv_nsec != 0
        )
    }
}
