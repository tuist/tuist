import Foundation
import TuistREAPI
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Rechecks file identities on every use; compiler and immutable artifact digests may be shared within a Cargo session.
final class CargoInputHasher {
    struct Identity: Codable, Equatable {
        let fields: [String]
        let precise: Bool
    }

    private struct Entry: Codable, Equatable {
        let identity: Identity
        let hash: String
        let size: Int64
    }

    /// The session's shared records as this process last read or wrote them. Compiler hooks are served from one
    /// process, so each record file is read once rather than decoded (and large inputs locked) on every lookup; the
    /// files remain for hooks in other processes and for records kept across sessions.
    private final class ProcessRecords: @unchecked Sendable {
        let lock = NSLock()
        var files: [String: Entry] = [:]
        var trees: [String: [String: Entry]] = [:]
        /// Record directories of sessions whose hooks this process serves: their records live here only.
        var served: Set<String> = []

        func isServed(_ directory: URL) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return served.contains(directory.path)
        }

        /// Gives a served session the records kept under `source` (persistent toolchain records) as its own.
        func serve(_ directory: URL, seededFrom source: URL?) {
            lock.lock()
            served.insert(directory.path)
            if let source {
                let prefix = source.path + "/"
                for (path, entry) in files where path.hasPrefix(prefix) {
                    files[directory.path + "/" + path.dropFirst(prefix.count)] = entry
                }
                for (path, records) in trees where path.hasPrefix(prefix) {
                    trees[directory.path + "/" + path.dropFirst(prefix.count)] = records
                    // Hooks look toolchain files up one by one (a recorded compilation's compiler files, the sysroot
                    // files rustc read), not through the tree, so each record is a file record of the session too.
                    for (file, entry) in records {
                        let memo = directory.path + "/" + REAPI.digest(Data(file.utf8)).hash
                        if files[memo] == nil { files[memo] = entry }
                    }
                }
            }
            lock.unlock()
        }

        func stopServing(_ directory: URL) {
            lock.lock()
            served.remove(directory.path)
            let prefix = directory.path + "/"
            files = files.filter { !$0.key.hasPrefix(prefix) }
            trees = trees.filter { !$0.key.hasPrefix(prefix) }
            lock.unlock()
        }

        func file(_ memo: URL) -> Entry? {
            lock.lock()
            defer { lock.unlock() }
            return files[memo.path]
        }

        func setFile(_ memo: URL, _ entry: Entry) {
            lock.lock()
            files[memo.path] = entry
            lock.unlock()
        }

        func tree(_ memo: URL) -> [String: Entry]? {
            lock.lock()
            defer { lock.unlock() }
            return trees[memo.path]
        }

        func setTree(_ memo: URL, _ records: [String: Entry]) {
            lock.lock()
            trees[memo.path] = records
            lock.unlock()
        }
    }

    private static let processRecords = ProcessRecords()

    /// Hooks of the session are served by this process, so its records stay in memory instead of being written as
    /// files for other processes; a hook in another process (the fallback) hashes for itself. Seeds them with the
    /// records this process holds under `seed`, such as the persistent toolchain records.
    static func serve(session: URL, seed: URL?) {
        processRecords.serve(
            session.appendingPathComponent("input-digests-v1"), seededFrom: seed?.appendingPathComponent("input-digests-v1")
        )
    }

    static func isServing(session: URL) -> Bool {
        processRecords.isServed(session.appendingPathComponent("input-digests-v1"))
    }

    static func stopServing(session: URL) {
        processRecords.stopServing(session.appendingPathComponent("input-digests-v1"))
    }

    private var inMemory: Bool { sharedDirectory.map(Self.processRecords.isServed) ?? false }

    private let identify: (URL) throws -> Identity
    private let hashFile: (URL) throws -> REAPI.Digest
    private let sharedDirectory: URL?
    private var entries: [URL: (Identity, REAPI.Digest)] = [:]
    private var supportedSources: Set<REAPI.Digest> = []
    private var loadedTrees: Set<URL> = []

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
            .appendingPathComponent(REAPI.digest(Data(file.path.utf8)).hash, isDirectory: false) : nil
        if let memo, let entry = Self.processRecords.file(memo), entry.identity == before {
            let digest = REAPI.Digest.with { $0.hash = entry.hash; $0.sizeBytes = entry.size }
            entries[file] = (before, digest)
            return digest
        }
        // Cargo starts many compilers at once: without this lock, each one hashes a large shared input such as
        // `librustc_driver` before any of them has recorded its digest.
        var lock: Int32 = -1
        defer { if lock >= 0 { close(lock) } }
        let inMemory = memo != nil && inMemory
        if let memo, Int(before.fields[2]).map({ $0 >= 1_000_000 }) == true, inMemory || (try? readEntry(memo)) == nil {
            try? FileManager.default.createDirectory(at: memo.deletingLastPathComponent(), withIntermediateDirectories: true)
            lock = open(memo.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            if lock >= 0 { _ = flock(lock, LOCK_EX) }
        }
        if inMemory, let memo, let entry = Self.processRecords.file(memo), entry.identity == before {
            let digest = REAPI.Digest.with { $0.hash = entry.hash; $0.sizeBytes = entry.size }
            entries[file] = (before, digest)
            return digest
        }
        if !inMemory, let memo, let entry = try? readEntry(memo), entry.identity == before {
            let digest = REAPI.Digest.with { $0.hash = entry.hash; $0.sizeBytes = entry.size }
            if (try? REAPI.validate(digest)) != nil, try identify(file) == before {
                entries[file] = (before, digest)
                Self.processRecords.setFile(memo, entry)
                return digest
            }
        }
        let digest = try hashFile(file)
        guard try identify(file) == before else { throw CargoCacheInvocation.CacheError.unsupported }
        if before.precise { entries[file] = (before, digest) }
        let entry = Entry(identity: before, hash: digest.hash, size: digest.sizeBytes)
        if let memo {
            if !inMemory, let data = try? JSONEncoder().encode(entry) {
                try? FileManager.default.createDirectory(at: memo.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: memo, options: .atomic)
            }
            Self.processRecords.setFile(memo, entry)
        }
        return digest
    }

    /// Records a digest computed elsewhere (a blob hashed as it was stored) for the file's current identity, so later
    /// sessions reuse it without hashing the file again.
    func remember(_ file: URL, digest: REAPI.Digest, when accepts: (Identity) -> Bool = { _ in true }) {
        guard let sharedDirectory, let identity = try? identify(file), identity.precise, accepts(identity) else { return }
        let entry = Entry(identity: identity, hash: digest.hash, size: digest.sizeBytes)
        let memo = sharedDirectory.appendingPathComponent(REAPI.digest(Data(file.path.utf8)).hash, isDirectory: false)
        if !inMemory, let data = try? JSONEncoder().encode(entry) {
            try? FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            try? data.write(to: memo, options: .atomic)
        }
        Self.processRecords.setFile(memo, entry)
    }

    private func readEntry(_ file: URL) throws -> Entry {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try JSONDecoder().decode(Entry.self, from: handle.read(upToCount: 4096) ?? Data())
    }

    /// Batch the session memo reads, never directory discovery or per-file identity checks.
    func withSharedDigests<T>(under root: URL, body: () throws -> T) throws -> T {
        guard let sharedDirectory, loadedTrees.insert(root).inserted else { return try body() }
        let memo = sharedDirectory.appendingPathComponent("tree-" + REAPI.digest(Data(root.path.utf8)).hash)
        let prefix = root.path + "/"
        // Already read or written by this process: the records seed identity checks, and the file is rewritten only
        // when they change.
        if let known = Self.processRecords.tree(memo) {
            load(known, prefix: prefix)
            let result = try body()
            let records = records(prefix: prefix)
            if records != known { save(records, to: memo) }
            return result
        }
        if inMemory {
            let result = try body()
            save(records(prefix: prefix), to: memo)
            return result
        }
        // Cargo starts many compilers at once. Without this lock each one hashes the whole toolchain
        // before any of them publishes the memo; with it, one hashes and the rest reuse its records.
        try? FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        let lock = open(memo.path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        if lock >= 0 { _ = flock(lock, LOCK_EX) }
        defer { if lock >= 0 { close(lock) } }
        var previous: [String: Entry] = [:]
        if let handle = try? FileHandle(forReadingFrom: memo) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: 2_000_001), data.count <= 2_000_000,
               let records = try? JSONDecoder().decode([String: Entry].self, from: data), records.count <= 10000
            {
                previous = records
                load(records, prefix: prefix)
            }
        }
        let result = try body()
        let records = records(prefix: prefix)
        if records != previous { save(records, to: memo) } else { Self.processRecords.setTree(memo, records) }
        return result
    }

    private func load(_ records: [String: Entry], prefix: String) {
        for (path, record) in records where path.hasPrefix(prefix) {
            let digest = REAPI.Digest.with { $0.hash = record.hash; $0.sizeBytes = record.size }
            let file = URL(fileURLWithPath: path, isDirectory: false)
            if (try? REAPI.validate(digest)) != nil, entries[file] == nil {
                entries[file] = (record.identity, digest)
            }
        }
    }

    private func records(prefix: String) -> [String: Entry] {
        entries.reduce(into: [String: Entry]()) { records, entry in
            if entry.key.path.hasPrefix(prefix) {
                records[entry.key.path] = Entry(identity: entry.value.0, hash: entry.value.1.hash, size: entry.value.1.sizeBytes)
            }
        }
    }

    private func save(_ records: [String: Entry], to memo: URL) {
        guard records.count <= 10000 else { return }
        if !inMemory {
            guard let data = try? JSONEncoder().encode(records), data.count <= 2_000_000 else { return }
            try? FileManager.default.createDirectory(at: memo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: memo, options: .atomic)
        }
        Self.processRecords.setTree(memo, records)
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

    static func identity(_ file: URL) throws -> Identity {
        var value = stat()
        guard lstat(file.path, &value) == 0, value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw CargoCacheInvocation.CacheError.unsupported
        }
        return identity(value)
    }

    /// The identity of a regular file whose status the caller already has, such as from a directory walk.
    static func identity(_ value: stat) -> Identity {
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
