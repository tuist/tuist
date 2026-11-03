import Foundation
import Path
import TuistREAPI

/// A library, proc-macro or binary compilation keyed by what rustc was seen reading (`CargoReadRecorder`), for compilations the
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
    /// A linked binary, the only output without an extension.
    var executableOutput: String? { files.first.flatMap { URL(fileURLWithPath: $0).pathExtension.isEmpty ? $0 : nil } }
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
        case "bin":
            // Linking reads every rlib of the dependency closure through `-L dependency=`, which the read set keys.
            // A build script's binary is stored before `CargoBuildScript` replaces it with a shim, and a hit installs one.
            #if os(macOS)
                guard emitted == ["dep-info", "link"] else { return nil }
                files = ["\(name)\(suffix)", "\(name)\(suffix).d"]
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
        let linksWithSystemLinker = kind == "proc-macro" || kind == "bin"
        if linksWithSystemLinker {
            inputs += try await CargoToolchainIdentity.linker(environment: environment, directory: directory, process: process)
            // The linker runs unrecorded and searches these directories for the native libraries build scripts built
            // or found, so what it can find there is keyed by content.
            for value in CargoCacheInputs.values("-L", in: arguments) {
                let parts = value.split(separator: "=", maxSplits: 1)
                let (searchKind, path) = parts.count == 2 ? (String(parts[0]), String(parts[1])) : ("all", value)
                guard ["native", "all"].contains(searchKind) else { continue }
                let searched = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
                guard !searched.path.hasPrefix(identity.sysroot.path + "/") else { continue }
                let libraries = ((try? FileManager.default.contentsOfDirectory(atPath: searched.path)) ?? [])
                    .filter(Self.isNativeLibrary).sorted()
                // A shared prefix such as Homebrew's holds hundreds; hashing all of them would cost more than linking.
                guard libraries.count <= 64 else { return nil }
                for name in libraries {
                    let file = searched.appendingPathComponent(name)
                    guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                    let digest = try inputHasher.digest(file, shared: true)
                    inputs += [file.path, digest.hash, String(digest.sizeBytes)]
                }
            }
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

    /// A file the system linker may take from a search directory: `-l` resolves to `lib<name>` with one of these
    /// extensions.
    static func isNativeLibrary(_ name: String) -> Bool {
        name.hasPrefix("lib") && ["a", "dylib", "tbd", "so"].contains(URL(fileURLWithPath: name).pathExtension)
    }

    var index: CargoReadIndex? {
        environment["TUIST_CARGO_CACHE_DIR"].map {
            CargoReadIndex(
                root: URL(fileURLWithPath: $0),
                declaredKey: declared,
                version: Self.keyVersion,
                environment: environment
            )
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
            keepsLinkedLibraries: linksWithSystemLinker,
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
    let targetLibdirPath: String
    let version: String
    let compilerPaths: [String]

    var sysroot: URL { URL(fileURLWithPath: sysrootPath) }
    var compilerFiles: [URL] { compilerPaths.map { URL(fileURLWithPath: $0) } }

    static func resolve(
        _ executable: String, environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoToolchainIdentity {
        let session = environment["TUIST_CARGO_SESSION"].map { URL(fileURLWithPath: $0) }
        func memo(_ name: String) -> URL? {
            session?.appendingPathComponent("toolchain-" + REAPI.digest(Data(name.utf8)).hash)
        }
        // A sysroot's own compiler is the same toolchain whatever rustup would select: build scripts name it by its
        // absolute path in `RUSTC`, and the session's other hooks by `rustc`.
        let named = memo("\(executable)\0\(environment["RUSTUP_TOOLCHAIN"] ?? "")")
        let own = executable.hasPrefix("/") ? memo("\(CargoRelocation.canonical(executable))\0sysroot compiler") : nil
        for memo in [own, named].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: memo),
               let identity = try? JSONDecoder().decode(CargoToolchainIdentity.self, from: data) { return identity }
        }
        let paths = try await process.capture(
            executable, arguments: ["--print", "sysroot", "--print", "target-libdir"], environment: environment,
            directory: directory
        ).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard paths.count == 2, paths.allSatisfy({ $0.hasPrefix("/") }) else { throw CargoCacheInvocation.CacheError.unsupported }
        let sysroot = paths[0]
        let root = URL(fileURLWithPath: sysroot).standardizedFileURL
        let compiler = root.appendingPathComponent("bin/rustc")
        // The sysroot's compiler answers without another pass through a rustup proxy.
        let version = try await process.capture(
            FileManager.default.isExecutableFile(atPath: compiler.path) ? compiler.path : executable, arguments: ["-vV"],
            environment: environment, directory: directory
        )
        let libraries = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("lib").path)) ?? []
        let compilers = [compiler.resolvingSymlinksInPath().path]
            + libraries.filter { $0.hasPrefix("librustc_driver") }.sorted().map { root.appendingPathComponent("lib/" + $0).path }
        let identity = CargoToolchainIdentity(
            sysrootPath: root.path, targetLibdirPath: paths[1], version: version, compilerPaths: compilers
        )
        if let data = try? JSONEncoder().encode(identity) {
            for memo in [
                named,
                memo("\(CargoRelocation.canonical(compiler.path))\0sysroot compiler"),
                memo("\(compilers[0])\0sysroot compiler"),
            ].compactMap({ $0 }) {
                try? data.write(to: memo, options: .atomic)
            }
        }
        return identity
    }

    /// Hashes the files strict keys take from the toolchain (top-level `lib`, the host target tree without `bin`, the
    /// compiler) into the session's shared records, so the first wave of compilers finds them instead of queueing
    /// behind one of them on the session lock. Each hook still checks every file's identity before reusing a record.
    func prewarm(session: URL, cache: URL?, served: Bool) {
        // Toolchains do not change between builds, so their records persist in the cache and every session starts
        // from them: a served session from this process's copy in memory, other hooks from copied files. Each record
        // is still checked against its file's identity before it is used.
        let records = cache?.appendingPathComponent("toolchain")
        let hasher = CargoInputHasher(sessionDirectory: records ?? session)
        defer {
            if served {
                CargoInputHasher.serve(session: session, seed: records)
            } else if let records {
                let from = records.appendingPathComponent("input-digests-v1")
                let to = session.appendingPathComponent("input-digests-v1")
                try? FileManager.default.createDirectory(at: to, withIntermediateDirectories: true)
                for name in (try? FileManager.default.contentsOfDirectory(atPath: from.path)) ?? []
                    where !name.hasSuffix(".lock")
                {
                    try? FileManager.default.copyItem(at: from.appendingPathComponent(name), to: to.appendingPathComponent(name))
                }
            }
        }
        let libraries = sysroot.appendingPathComponent("lib")
        let host = URL(fileURLWithPath: targetLibdirPath).standardizedFileURL.deletingLastPathComponent()
        _ = try? hasher.withSharedDigests(under: libraries) {
            var files = (try? FileManager.default.contentsOfDirectory(at: libraries, includingPropertiesForKeys: nil)) ?? []
            if let tree = FileManager.default.enumerator(at: host, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let file as URL in tree {
                    if file.lastPathComponent == "bin", file.deletingLastPathComponent().standardizedFileURL == host {
                        tree.skipDescendants()
                    } else {
                        files.append(file)
                    }
                }
            }
            for file in files {
                let properties = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if properties?.isRegularFile == true, properties?.isSymbolicLink != true { _ = try? hasher.digest(
                    file,
                    shared: true
                ) }
            }
        }
        for compiler in compilerFiles {
            _ = try? hasher.digest(compiler, shared: true)
        }
    }

    /// The system linker and SDK a proc macro or build script is linked with, which the recorder cannot observe.
    static func linker(environment: [String: String], directory: AbsolutePath, process: CargoProcess) async throws -> [String] {
        let memo = environment["TUIST_CARGO_SESSION"].map { URL(fileURLWithPath: $0).appendingPathComponent("linker-identity") }
        if let memo, let data = try? Data(contentsOf: memo), let values = try? JSONDecoder().decode([String].self, from: data) {
            return values
        }
        // The answers persist with what selects them, as the `cc` shim's probe does: the developer directory and the
        // identities of the files `xcrun` would find. A selection through `SDKROOT` or `TOOLCHAINS` is probed per session.
        let selection: [String]? = {
            guard environment["SDKROOT"] == nil, environment["TOOLCHAINS"] == nil,
                  let developer = environment["DEVELOPER_DIR"]
                  ?? (try? FileManager.default.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"))
            else { return nil }
            let xcode = FileManager.default.fileExists(atPath: developer + "/Toolchains/XcodeDefault.xctoolchain")
            let tools = developer + (xcode ? "/Toolchains/XcodeDefault.xctoolchain/usr/bin" : "/usr/bin")
            let sdk = developer + (xcode ? "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" : "/SDKs/MacOSX.sdk")
            var identities = [developer]
            for path in [tools + "/clang", tools + "/ld", sdk + "/SDKSettings.json"] {
                var info = stat()
                guard stat(path, &info) == 0 else { return nil }
                identities.append(
                    "\(path):\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)"
                )
            }
            return identities
        }()
        let persistent = selection == nil ? nil : environment["TUIST_CARGO_CACHE_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("toolchain/linker-identity") }
        if let persistent, let data = try? Data(contentsOf: persistent),
           let stored = try? JSONDecoder().decode([[String]].self, from: data), stored.count == 2, stored[0] == selection
        {
            if let memo, let data = try? JSONEncoder().encode(stored[1]) { try? data.write(to: memo, options: .atomic) }
            return stored[1]
        }
        var values: [String] = []
        for arguments in [["--show-sdk-path"], ["--show-sdk-build-version"], ["clang", "--version"], ["ld", "-v"]] {
            let output = try await process.captureOutput(
                "/usr/bin/xcrun", arguments: arguments, environment: environment, directory: directory
            )
            values.append(String(decoding: output.stdout + output.stderr, as: UTF8.self))
        }
        if let memo, let data = try? JSONEncoder().encode(values) { try? data.write(to: memo, options: .atomic) }
        if let persistent, let selection, let data = try? JSONEncoder().encode([selection, values]) {
            try? FileManager.default.createDirectory(
                at: persistent.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: persistent, options: .atomic)
        }
        return values
    }
}
