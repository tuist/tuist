import FileSystem
import Foundation
import Path
import TuistREAPI

/// Resolve Rust inputs without hashing the concurrently changing Cargo output directory.
struct CargoCacheInputs {
    let sources: [URL]
    let externs: [URL]

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

    private final class Proofs: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: Set<String> = []

        func contains(_ path: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return paths.contains(path)
        }

        func insert(_ path: String) {
            lock.lock()
            paths.insert(path)
            lock.unlock()
        }
    }

    private static let servedProofs = Proofs()

    static func values(_ name: String, in arguments: [String]) -> [String] {
        arguments.enumerated().compactMap { index, value in
            if value == name, index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix(name + "=") ? String(value.dropFirst(name.count + 1)) : nil
        }
    }
}
