import Foundation
import Path
import TuistREAPI

/// A library or proc-macro compilation keyed by what rustc was seen reading (`CargoReadRecorder`), for compilations the
/// strict admission in `CargoCacheInvocation` cannot key in advance: proc-macro users, assembly, native libraries and
/// dependencies of those. Found in two steps: the declared key (relocated arguments, keyed environment, externs by
/// content, toolchain) selects the read set of an earlier run, and that set's current contents complete the key.
/// Its outputs are never certified for strict dependents, which therefore take this path as well.
struct CargoRecordedInvocation: CargoCacheAction {
    let arguments: [String]
    let environment: [String: String]
    let directory: AbsolutePath
    let output: URL
    let name: String
    let files: [String]
    var key: REAPI.Digest
    let declared: REAPI.Digest
    var reads: CargoReadSet?
    let relocation: CargoRelocation
    let inputHasher: CargoInputHasher
    let recorder: String
    let toolchain: URL
    let externs: [URL]
    let linksWithSystemLinker: Bool

    static let keyVersion = "tuist-swift-cargo-recorded-v1"
    var cacheVersion: String { Self.keyVersion }
    var kind: String { "rust" }
    var remapArguments: [String] { relocation.remapArguments }
    func storedOutput(_ data: Data) -> Data? { relocation.relative(data) }
    func restoredOutput(_ data: Data) -> Data? { relocation.absolute(data) }

    func unkeyedRoots(in data: Data) -> [String] {
        let keyed = Set((reads?.entries ?? []).filter { $0.kind == "root" }.map(\.name))
        return relocation.boundRoots(in: data).filter { !keyed.contains($0.placeholder) }.map(\.path)
    }

    static func prepare(
        _ arguments: [String], environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoRecordedInvocation? {
        guard environment["TUIST_CARGO_CACHE_DIR"] != nil, let recorder = environment["TUIST_CARGO_RECORDER"],
              environment["TUIST_CARGO_INNER_WRAPPER"] == nil,
              environment["RUSTC_WORKSPACE_WRAPPER"].map(\.isEmpty) ?? true,
              !environment.keys.contains(where: { $0.hasPrefix("LD_") || $0.hasPrefix("DYLD_") }),
              let executable = arguments.first, URL(fileURLWithPath: executable).lastPathComponent == "rustc",
              !arguments.contains(where: {
                  $0.hasPrefix("@") || $0.hasPrefix("--print") || $0 == "--test" || $0 == "-o"
                      || $0.hasPrefix("--remap-path-prefix") || $0.hasPrefix("--sysroot") || $0.hasSuffix(".json")
                      || $0.hasPrefix("incremental=") || $0.hasPrefix("-Cincremental") || $0.hasPrefix("-Zincremental")
              }),
              let name = CargoCacheInputs.values("--crate-name", in: arguments).first,
              !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
              let kind = CargoCacheInputs.values("--crate-type", in: arguments).first,
              CargoCacheInputs.values("--crate-type", in: arguments).count == 1,
              let emit = CargoCacheInputs.values("--emit", in: arguments).first,
              let out = CargoCacheInputs.values("--out-dir", in: arguments).first,
              arguments.dropFirst().contains(where: { $0.hasSuffix(".rs") })
        else { return nil }
        let suffix = CargoCacheInputs.values("-C", in: arguments).first(where: { $0.hasPrefix("extra-filename=") })
            .map { String($0.dropFirst(15)) } ?? ""
        guard suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        let emitted = Set(emit.split(separator: ",").map(String.init))
        let files: [String]
        switch kind {
        case "lib", "rlib":
            guard emitted == ["dep-info", "metadata", "link"] else { return nil }
            files = ["lib\(name)\(suffix).rlib", "lib\(name)\(suffix).rmeta", "\(name)\(suffix).d"]
        case "proc-macro":
            #if os(macOS)
                guard emitted == ["dep-info", "link"] else { return nil }
                files = ["lib\(name)\(suffix).dylib", "\(name)\(suffix).d"]
            #else
                return nil
            #endif
        default:
            return nil
        }
        let identity = try await CargoToolchainIdentity.resolve(
            executable, environment: environment, directory: directory, process: process
        )
        let relocation = CargoRelocation(environment: environment, sysroot: identity.sysroot)
        let inputHasher = CargoInputHasher(sessionDirectory: environment["TUIST_CARGO_SESSION"].map { URL(fileURLWithPath: $0) })
        let base = URL(fileURLWithPath: directory.pathString)
        var inputs = [
            keyVersion, CargoReadRecorder.version, directory.pathString, identity.version,
        ]
        inputs += arguments.dropFirst().filter { !$0.hasPrefix("--diagnostic-width") }
        inputs += environment.sorted { $0.key < $1.key }.filter { !CargoCacheInvocation.isIgnored($0.key) }
            .map { "\($0.key)=\($0.value)" }
        var externs: [URL] = []
        for value in CargoCacheInputs.values("--extern", in: arguments) {
            let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            let file = URL(fileURLWithPath: String(parts[1]), relativeTo: base).standardizedFileURL
            let digest = try inputHasher.digest(file, shared: true)
            inputs += [file.path, digest.hash, String(digest.sizeBytes)]
            externs.append(file)
        }
        for compiler in identity.compilerFiles {
            let digest = try inputHasher.digest(compiler, shared: true)
            inputs += [compiler.path, digest.hash, String(digest.sizeBytes)]
        }
        let linksWithSystemLinker = kind == "proc-macro"
        if linksWithSystemLinker {
            inputs += try await CargoToolchainIdentity.linker(environment: environment, directory: directory, process: process)
        }
        inputs += relocation.remapArguments
        let declared = REAPI.digest(try JSONEncoder().encode(inputs.map(relocation.relative)))
        return CargoRecordedInvocation(
            arguments: arguments, environment: environment, directory: directory,
            output: URL(fileURLWithPath: out, relativeTo: base).standardizedFileURL, name: name, files: files,
            key: declared, declared: declared, reads: nil, relocation: relocation, inputHasher: inputHasher,
            recorder: recorder, toolchain: identity.sysroot, externs: externs, linksWithSystemLinker: linksWithSystemLinker
        )
    }

    var index: CargoReadIndex? {
        environment["TUIST_CARGO_CACHE_DIR"].map {
            CargoReadIndex(root: URL(fileURLWithPath: $0), declaredKey: declared, version: Self.keyVersion)
        }
    }

    func fingerprint() throws -> REAPI.Digest {
        guard let reads else { throw CargoCacheInvocation.CacheError.unsupported }
        let state = try reads.evaluate(
            relocation: relocation, environment: environment, hasher: inputHasher,
            volatileEnvironment: Self.isVolatile
        )
        return REAPI.digest(try JSONEncoder().encode([declared.hash] + state))
    }

    /// Takes a recorded set as this invocation's inputs. `nil` when its inputs cannot be read now.
    func with(_ reads: CargoReadSet) -> CargoRecordedInvocation? {
        var candidate = self
        candidate.reads = reads
        guard let key = try? candidate.fingerprint() else { return nil }
        candidate.key = key
        return candidate
    }

    /// The environment of the recorded compilation.
    func recordingEnvironment(log: URL) -> [String: String] {
        CargoReadRecorder.environment(environment, library: recorder, log: log, toolchain: toolchain.path)
    }

    /// The inputs of a finished, successful recorded compilation, or `nil` when it cannot be cached.
    func recorded(log: URL, started: Date) -> CargoRecordedInvocation? {
        let excluded = ["TUIST_CARGO_SESSION", "TUIST_CARGO_CACHE_DIR"].compactMap { environment[$0] }
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path } + [log.path]
        let temporary = [NSTemporaryDirectory(), "/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let linker = CargoCacheInputs.values("-C", in: arguments).first(where: { $0.hasPrefix("linker=") })
            .map { URL(fileURLWithPath: String($0.dropFirst(7))).lastPathComponent }
        guard var reads = CargoReadSet.parse(
            log: log, relocation: relocation, excludedRoots: excluded,
            targetDirectory: environment["TUIST_CARGO_TARGET_DIR"].map { URL(fileURLWithPath: $0).standardizedFileURL.path },
            allowedWrites: [output.path] + temporary,
            allowedSpawn: { [linksWithSystemLinker] path in
                guard linksWithSystemLinker else { return false }
                let program = URL(fileURLWithPath: path).lastPathComponent
                // rustc finds the SDK with `xcrun` and links with `cc`; both are keyed by `CargoToolchainIdentity.linker`.
                return ["cc", "xcrun"].contains(program) || program == linker
            },
            keyedEnvironment: { !CargoCacheInvocation.isIgnored($0) }
        ),
            let depInfo = try? String(contentsOf: output.appendingPathComponent(files.last!), encoding: .utf8)
        else { return nil }
        reads.addEnvironmentDependencies(depInfo, keyedEnvironment: { !CargoCacheInvocation.isIgnored($0) })
        guard reads.unchanged(since: started, relocation: relocation) else { return nil }
        // Outputs that name a root behave the same only at that root, so their key names it too.
        for file in (try? outputFiles()) ?? [] where !file.hasSuffix(".d") {
            guard let data = try? Data(contentsOf: output.appendingPathComponent(file)) else { return nil }
            reads.bind(relocation.boundRoots(in: data))
        }
        return with(reads)
    }

    static func isVolatile(_ name: String) -> Bool {
        CargoCacheInvocation.ignoredEnvironment.contains(name)
            || CargoCacheInvocation.ignoredEnvironmentPrefixes.contains(where: name.hasPrefix)
            || ["PWD", "TMPDIR", "NUM_JOBS"].contains(name)
    }

    func validateDependencies(restoring _: Bool) async throws {}

    /// Recorded outputs establish no admission for strict dependents: their backend reads are known only by recording.
    func certifyOutputs(metadataOnly _: Bool) throws {}

    func acceptsOutput(_ file: String) -> Bool {
        if files.contains(file) { return true }
        let prefix = String(files.last!.dropLast(2)) + "."
        return file.hasPrefix(prefix) && ["o", "dwo", "dwp"].contains(URL(fileURLWithPath: file).pathExtension)
            && file.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    func outputFiles() throws -> [String] {
        let additional = try FileManager.default.contentsOfDirectory(atPath: output.path)
            .filter { !files.contains($0) && acceptsOutput($0) }.sorted()
        guard files.count + additional.count <= 128 else { throw CargoCacheInvocation.CacheError.unsupported }
        return files + additional
    }
}

/// The compiler a hook runs, resolved once per Cargo session.
struct CargoToolchainIdentity: Codable {
    let sysrootPath: String
    let version: String
    let compilerPaths: [String]

    var sysroot: URL { URL(fileURLWithPath: sysrootPath) }
    var compilerFiles: [URL] { compilerPaths.map { URL(fileURLWithPath: $0) } }

    static func resolve(
        _ executable: String, environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoToolchainIdentity {
        let memo = environment["TUIST_CARGO_SESSION"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(
                "toolchain-" + REAPI.digest(Data("\(executable)\0\(environment["RUSTUP_TOOLCHAIN"] ?? "")".utf8)).hash
            )
        }
        if let memo, let data = try? Data(contentsOf: memo),
           let identity = try? JSONDecoder().decode(CargoToolchainIdentity.self, from: data) { return identity }
        let sysroot = try await process.capture(
            executable, arguments: ["--print", "sysroot"], environment: environment, directory: directory
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let version = try await process.capture(executable, arguments: ["-vV"], environment: environment, directory: directory)
        guard sysroot.hasPrefix("/") else { throw CargoCacheInvocation.CacheError.unsupported }
        let root = URL(fileURLWithPath: sysroot).standardizedFileURL
        let libraries = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("lib").path)) ?? []
        let compilers = [root.appendingPathComponent("bin/rustc").resolvingSymlinksInPath().path]
            + libraries.filter { $0.hasPrefix("librustc_driver") }.sorted().map { root.appendingPathComponent("lib/" + $0).path }
        let identity = CargoToolchainIdentity(sysrootPath: root.path, version: version, compilerPaths: compilers)
        if let memo, let data = try? JSONEncoder().encode(identity) { try? data.write(to: memo, options: .atomic) }
        return identity
    }

    /// The system linker and SDK a proc macro or build script is linked with, which the recorder cannot observe.
    static func linker(environment: [String: String], directory: AbsolutePath, process: CargoProcess) async throws -> [String] {
        let memo = environment["TUIST_CARGO_SESSION"].map { URL(fileURLWithPath: $0).appendingPathComponent("linker-identity") }
        if let memo, let data = try? Data(contentsOf: memo), let values = try? JSONDecoder().decode([String].self, from: data) {
            return values
        }
        var values: [String] = []
        for arguments in [["--show-sdk-path"], ["--show-sdk-build-version"], ["clang", "--version"], ["ld", "-v"]] {
            let output = try await process.captureOutput(
                "/usr/bin/xcrun", arguments: arguments, environment: environment, directory: directory
            )
            values.append(String(decoding: output.stdout + output.stderr, as: UTF8.self))
        }
        if let memo, let data = try? JSONEncoder().encode(values) { try? data.write(to: memo, options: .atomic) }
        return values
    }
}
