import FileSystem
import Foundation
import Path
import Synchronization
import TuistREAPI

/// Resolve Rust inputs without hashing the concurrently changing Cargo output directory.
struct CargoCacheInputs {
    let sources: [URL]
    let externs: [URL]

    /// The names in `directory` that start with `prefix`. `readdir` returns names alone, where `FileManager` also reads
    /// every entry's attributes, and a target's `deps` holds tens of thousands of files, listed for every compilation
    /// published: `FileManager` took 87 ms per listing there, `readdir` 10.
    static func entries(of directory: URL, prefix: String) throws -> [String] {
        guard let handle = opendir(directory.path) else { throw CargoCacheInvocation.CacheError.unsupported }
        defer { closedir(handle) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(handle) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(cString: $0)
                }
            }
            if name.hasPrefix(prefix) { names.append(name) }
        }
        guard errno == 0 else { throw CargoCacheInvocation.CacheError.unsupported }
        return names
    }

    static func resolveExterns(
        arguments: [String], environment: [String: String], directory: AbsolutePath,
        inputHasher: CargoInputHasher
    ) throws -> [URL] {
        let base = URL(fileURLWithPath: directory.pathString)
        return try values("--extern", in: arguments).map { value in
            let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw CargoCacheInvocation.CacheError.unsupported
            }
            let file = URL(fileURLWithPath: String(parts[1]), relativeTo: base).standardizedFileURL
            let digest = try inputHasher.digest(file, shared: true)
            try validateDependency(file, digest: digest, environment: environment)
            return file
        }
    }

    static func discover(
        arguments: [String], environment: [String: String], directory: AbsolutePath,
        externs: [URL], process: CargoProcess
    ) async throws -> CargoCacheInputs {
        let base = URL(fileURLWithPath: directory.pathString)
        return try await FileSystem().runInTemporaryDirectory(prefix: "tuist-cargo-inputs") { temporary in
            let root = URL(fileURLWithPath: temporary.pathString)
            let depInfo = root.appendingPathComponent("inputs.d")
            var probe: [String] = []
            var index = 1
            while index < arguments.count {
                let value = arguments[index]
                if value == "--emit" {
                    index += 2
                    continue
                }
                if !value.hasPrefix("--emit=") { probe.append(value) }
                index += 1
            }
            probe.append("--emit=dep-info=\(depInfo.path)")
            _ = try await process.capture(arguments[0], arguments: probe, environment: environment, directory: directory)
            guard try depInfo.resourceValues(forKeys: [.fileSizeKey]).fileSize.map({ $0 < 2_000_000 }) == true
            else { throw CargoCacheInvocation.CacheError.unsupported }
            let text = try String(contentsOf: depInfo, encoding: .utf8)
            try CargoCacheInvocation.validateEnvironmentDependencies(text)
            let sources = try CargoCacheInvocation.dependencies(text).map {
                URL(fileURLWithPath: $0, relativeTo: base).standardizedFileURL
            }
            guard !sources.isEmpty, sources.count <= 10000 else { throw CargoCacheInvocation.CacheError.unsupported }
            let uniqueSources = Set(sources).sorted { $0.path < $1.path }
            for file in uniqueSources {
                guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize.map({ $0 <= 2_000_000 }) == true
                else { throw CargoCacheInvocation.CacheError.unsupported }
            }
            return CargoCacheInputs(
                sources: uniqueSources,
                externs: Set(externs).sorted { $0.path < $1.path }
            )
        }
    }

    /// A dependency can export generic MIR or macros containing late assembler reads. A fresh
    /// dep-info probe alone does not observe those reads. Require the same source admission for
    /// its entire dependency closure, certified against the exact artifact bytes in this session.
    static func validateDependency(_ file: URL, digest: REAPI.Digest, environment: [String: String]) throws {
        guard ["rlib", "rmeta"].contains(file.pathExtension), isCertified(digest, environment: environment) else {
            throw CargoCacheInvocation.CacheError.unsupported
        }
    }

    /// Whether this session certified the artifact bytes of `digest`.
    static func isCertified(_ digest: REAPI.Digest, environment: [String: String]) -> Bool {
        guard let session = environment["TUIST_CARGO_SESSION"], let proof = proofPath(digest, environment: environment)
        else { return false }
        if CargoInputHasher.isServing(session: URL(fileURLWithPath: session)), servedProofs.contains(proof) { return true }
        guard let handle = FileHandle(forReadingAtPath: proof) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 128)) == Data(CargoCacheInvocation.keyVersion.utf8)
    }

    /// Certifies the artifact bytes of `digest` for the session. A session whose hooks this process serves keeps its
    /// proofs in memory, as it keeps its input digests: no other process reads them, and a warm build restores
    /// hundreds. Otherwise each proof is a file, written atomically, that hooks in other processes read.
    static func certify(_ digest: REAPI.Digest, environment: [String: String]) throws {
        guard let session = environment["TUIST_CARGO_SESSION"], let proof = proofPath(digest, environment: environment)
        else { return }
        if CargoInputHasher.isServing(session: URL(fileURLWithPath: session)) {
            servedProofs.insert(proof)
            return
        }
        let file = URL(fileURLWithPath: proof)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(CargoCacheInvocation.keyVersion.utf8).write(to: file, options: .atomic)
    }

    private static func proofPath(_ digest: REAPI.Digest, environment: [String: String]) -> String? {
        environment["TUIST_CARGO_SESSION"].map { $0 + "/safe-rust-artifacts/" + digest.hash }
    }

    private final class Proofs: Sendable {
        private let paths = Mutex<Set<String>>([])

        func contains(_ path: String) -> Bool {
            paths.withLock { $0.contains(path) }
        }

        func insert(_ path: String) {
            _ = paths.withLock { $0.insert(path) }
        }
    }

    private static let servedProofs = Proofs()

    /// The arguments without `-C incremental=<directory>`. Incremental compilation only reuses this machine's earlier
    /// work towards equivalent outputs, so compilations with and without it share entries: Cargo enables it for
    /// workspace crates in the `dev` profile, and keying it would cache none of them for builds without it, such as CI.
    static func withoutIncremental(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "-C", index + 1 < arguments.count, arguments[index + 1].hasPrefix("incremental=") {
                index += 2
            } else {
                if !arguments[index].hasPrefix("-Cincremental=") { result.append(arguments[index]) }
                index += 1
            }
        }
        return result
    }

    /// The directory of `-C incremental=<directory>`, where rustc keeps its incremental session.
    static func incrementalDirectory(_ arguments: [String], directory: AbsolutePath) -> URL? {
        let codegen = arguments.enumerated().compactMap { index, value -> String? in
            if value == "-C", index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix("-C") ? String(value.dropFirst(2)) : nil
        }
        return codegen.last(where: { $0.hasPrefix("incremental=") }).map {
            URL(fileURLWithPath: String($0.dropFirst(12)), relativeTo: URL(fileURLWithPath: directory.pathString))
                .standardizedFileURL
        }
    }

    static func values(_ name: String, in arguments: [String]) -> [String] {
        arguments.enumerated().compactMap { index, value in
            if value == name, index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix(name + "=") ? String(value.dropFirst(name.count + 1)) : nil
        }
    }
}
