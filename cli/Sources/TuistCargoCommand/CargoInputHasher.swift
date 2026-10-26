import Foundation
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Rechecks file identities on every use; only toolchain digests may be shared within a Cargo session.
final class CargoInputHasher {
    struct Identity: Codable, Equatable {
        let fields: [String]
        let precise: Bool
    }

    private struct Entry: Codable {
        let identity: Identity
        let hash: String
        let size: Int64
    }

    private let identify: (URL) throws -> Identity
    private let hashFile: (URL) throws -> REAPI.Digest
    private let sharedDirectory: URL?
    private var entries: [URL: (Identity, REAPI.Digest)] = [:]
    private var supportedSources: Set<REAPI.Digest> = []

    init(
        sessionDirectory: URL? = nil,
        identify: @escaping (URL) throws -> Identity = CargoInputHasher.identity,
        hashFile: @escaping (URL) throws -> REAPI.Digest = REAPI.digest(file:)
    ) {
        sharedDirectory = sessionDirectory?.appendingPathComponent("input-digests-v1")
        self.identify = identify
        self.hashFile = hashFile
    }

    func digest(_ file: URL, shared: Bool = false) throws -> REAPI.Digest {
        let before = try identify(file)
        if before.precise, let (identity, digest) = entries[file], identity == before { return digest }
        let memo = shared && before.precise ? sharedDirectory?
            .appendingPathComponent(REAPI.digest(Data(file.path.utf8)).hash) : nil
        if let memo, let entry = try? readEntry(memo), entry.identity == before {
            let digest = REAPI.Digest.with { $0.hash = entry.hash; $0.sizeBytes = entry.size }
            if (try? REAPI.validate(digest)) != nil, try identify(file) == before {
                entries[file] = (before, digest)
                return digest
            }
        }
        let digest = try hashFile(file)
        guard try identify(file) == before else { throw CargoCacheInvocation.CacheError.unsupported }
        if before.precise { entries[file] = (before, digest) }
        if let memo, let data = try? JSONEncoder().encode(Entry(identity: before, hash: digest.hash, size: digest.sizeBytes)) {
            try? FileManager.default.createDirectory(at: memo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: memo, options: .atomic)
        }
        return digest
    }

    private func readEntry(_ file: URL) throws -> Entry {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try JSONDecoder().decode(Entry.self, from: handle.read(upToCount: 4096) ?? Data())
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
