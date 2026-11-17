import FileSystem
import Foundation
import Path
import Synchronization
import TuistREAPI

/// Resolve Rust inputs without hashing the concurrently changing Cargo output directory.
struct CargoCacheInputs {
    let sources: [URL]
    let externs: [URL]
    /// Variables keyed only when read (`CargoCacheInvocation.isKeyedWhenRead`) that dep-info says the crate read.
    var variables: [String] = []

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
        externs: [URL], process: CargoProcess, clippy: Bool
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
            try CargoCacheInvocation.validateEnvironmentDependencies(text, clippy: clippy)
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
                externs: Set(externs).sorted { $0.path < $1.path },
                variables: CargoCacheInvocation.readVariables(text)
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

    /// The arguments a compilation the cache missed runs with on CI: without `-C incremental` when this target has
    /// neither compiled the crate before nor holds a session of it, as in a fresh checkout. That first
    /// compilation is a full one either way, and building its session costs a quarter more than compiling without one
    /// (Codex's `codex-core`: 73 s against 55 s). Keys leave the option out, so the entry is shared either way. The
    /// target remembers the unit (`<incremental>/.tuist-compiled`, which `cargo clean` removes with the sessions), so
    /// its next compilation there, as in a CI job that keeps its target directory, runs incrementally as Cargo asked.
    /// Whatever cannot be remembered keeps the option.
    static func withoutFirstIncrementalSession(_ arguments: [String], directory: AbsolutePath) -> [String] {
        guard let sessions = incrementalDirectory(arguments, directory: directory),
              let name = values("--crate-name", in: arguments).first, !name.isEmpty
        else { return arguments }
        let codegen = values("-C", in: arguments) + arguments.filter { $0.hasPrefix("-C") && $0.count > 2 }
            .map { String($0.dropFirst(2)) }
        let unit = name + (codegen.last(where: { $0.hasPrefix("extra-filename=") }).map { String($0.dropFirst(15)) } ?? "")
        guard !unit.contains("/"), !unit.hasPrefix(".") else { return arguments }
        let marker = sessions.appendingPathComponent(".tuist-compiled").appendingPathComponent(unit)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return arguments }
        // A session from before the target remembered units (rustc names it `<crate>-<stable crate id>`).
        let hasSession = ((try? FileManager.default.contentsOfDirectory(atPath: sessions.path)) ?? [])
            .contains { $0.hasPrefix(name + "-") }
        guard (try? FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true
        )) != nil, FileManager.default.createFile(atPath: marker.path, contents: nil) else { return arguments }
        return hasSession ? arguments : withoutIncremental(arguments)
    }

    /// The arguments a key holds: without incremental compilation's directory, a front-end thread count or a terminal
    /// width, none of which changes what rustc produces.
    static func keyArguments(_ arguments: [String]) -> [String] {
        withoutDiagnosticWidth(withoutThreadCount(withoutIncremental(arguments)).arguments)
    }

    /// What every valid `-Z threads=<count>` becomes in keys.
    static let threadCount = "-Zthreads=0"

    /// The arguments with a single valid `-Z threads=<count>` replaced by `threadCount`, and whether there was one.
    /// rustc marks the option untracked: it sets how many threads the front end runs, not what it produces, so builds
    /// with different counts share entries. Its presence stays keyed, because a toolchain that rejects `-Z` fails with
    /// it. A malformed or repeated option leaves the arguments as they are, so a cached success cannot hide rustc's
    /// error about it; such arguments still hold that option, which normalized ones never do. So does any `-j` or
    /// `--jobs*` option: rustc fails when the count exceeds it, and a count of 0 is the machine's parallelism.
    static func withoutThreadCount(_ arguments: [String]) -> (arguments: [String], normalized: Bool) {
        guard !arguments.contains(where: { $0.hasPrefix("-j") || $0.hasPrefix("--jobs") }) else { return (arguments, false) }
        var result: [String] = []
        var normalized = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            let separate = argument == "-Z" && index + 1 < arguments.count && arguments[index + 1].hasPrefix("threads")
            guard separate || argument.hasPrefix("-Zthreads") else {
                result.append(argument)
                index += 1
                continue
            }
            let option = separate ? arguments[index + 1] : String(argument.dropFirst(2))
            let value = option.hasPrefix("threads=") ? String(option.dropFirst(8)) : ""
            guard !normalized, (1 ... 3).contains(value.count), value.allSatisfy({ "0123456789".contains($0) }),
                  let count = Int(value, radix: 10), count <= 255
            else { return (arguments, false) }
            normalized = true
            result.append(threadCount)
            index += separate ? 2 : 1
        }
        return (result, normalized)
    }

    /// The arguments without a single valid `--diagnostic-width`, which only sets where rendered diagnostics wrap
    /// (stored diagnostics carry their width instead). Invalid or repeated widths stay, so a cached success cannot hide
    /// rustc's error about them.
    static func withoutDiagnosticWidth(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var seen = false
        var index = 0
        while index < arguments.count {
            let parts = arguments[index].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard parts.first == "--diagnostic-width" else {
                result.append(arguments[index])
                index += 1
                continue
            }
            let value = parts.count == 2 ? parts[1] : (index + 1 < arguments.count ? arguments[index + 1] : "")
            guard !seen, !value.hasPrefix("-"), let width = Int(value, radix: 10), width >= 0 else { return arguments }
            seen = true
            index += parts.count == 2 ? 1 : 2
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
