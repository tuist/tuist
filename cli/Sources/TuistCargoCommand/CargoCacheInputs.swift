import FileSystem
import Foundation
import Path
import TuistREAPI

/// Resolve Rust inputs without hashing the concurrently changing Cargo output directory.
struct CargoCacheInputs {
    let sources: [URL]
    let externs: [URL]

    static func discover(
        arguments: [String], environment: [String: String], directory: AbsolutePath,
        inputHasher: CargoInputHasher, process: CargoProcess
    ) async throws -> CargoCacheInputs {
        let base = URL(fileURLWithPath: directory.pathString)
        let externs = try values("--extern", in: arguments).map { value in
            let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw CargoCacheInvocation.CacheError.unsupported
            }
            let file = URL(fileURLWithPath: String(parts[1]), relativeTo: base).standardizedFileURL
            let digest = try inputHasher.digest(file, shared: true)
            try validateDependency(file, digest: digest, environment: environment)
            return file
        }
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
            return CargoCacheInputs(
                sources: Set(sources).sorted { $0.path < $1.path },
                externs: Set(externs).sorted { $0.path < $1.path }
            )
        }
    }

    /// A dependency can export generic MIR or macros containing late assembler reads. A fresh
    /// dep-info probe alone does not observe those reads. Require the same source admission for
    /// its entire dependency closure, certified against the exact artifact bytes in this session.
    static func validateDependency(_ file: URL, digest: REAPI.Digest, environment: [String: String]) throws {
        guard ["rlib", "rmeta"].contains(file.pathExtension),
              let proof = proofPath(digest, environment: environment),
              let handle = try? FileHandle(forReadingFrom: proof)
        else {
            throw CargoCacheInvocation.CacheError.unsupported
        }
        defer { try? handle.close() }
        guard try handle.read(upToCount: 128) == Data(CargoCacheInvocation.keyVersion.utf8) else {
            throw CargoCacheInvocation.CacheError.unsupported
        }
    }

    static func proofPath(_ digest: REAPI.Digest, environment: [String: String]) -> URL? {
        environment["TUIST_CARGO_SESSION"].map {
            URL(fileURLWithPath: $0).appendingPathComponent("safe-rust-artifacts/" + digest.hash)
        }
    }

    static func values(_ name: String, in arguments: [String]) -> [String] {
        arguments.enumerated().compactMap { index, value in
            if value == name, index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix(name + "=") ? String(value.dropFirst(name.count + 1)) : nil
        }
    }
}
