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
    /// The `.dSYM` a linked binary is stored with when its debug map names objects (`hasDebugMap`).
    let debugBundle: String?
    /// The program a miss runs recorded: the toolchain's own rustc, or its `clippy-driver` for `cargo clippy`.
    let program: String

    static let keyVersion = "tuist-swift-cargo-recorded-v2"
    var cacheVersion: String { Self.keyVersion }
    var kind: String { "rust" }
    /// A linked binary, the only output without an extension.
    var executableOutput: String? { files.first.flatMap { URL(fileURLWithPath: $0).pathExtension.isEmpty ? $0 : nil } }
    var remapArguments: [String] { relocation.remapArguments }
    func storedOutput(_ data: Data) -> Data? { relocation.relative(data) }
    func restoredOutput(_ data: Data) -> Data? { relocation.absolute(data) }

    func unkeyedRoots(in file: URL) throws -> [String] {
        // A `.dSYM` holds only debug information, like the binary's link-edit segment `boundRoots` skips.
        if let debugBundle, file.path.hasPrefix(output.appendingPathComponent(debugBundle).path + "/") { return [] }
        let keyed = Set((reads?.entries ?? []).filter { $0.kind == "root" }.map(\.name))
        return try relocation.boundRoots(of: file).filter { !keyed.contains($0.placeholder) }.map(\.path)
    }

    static func prepare(
        _ arguments: [String], environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoRecordedInvocation? {
        // `cargo clippy` starts the workspace's crates as `clippy-driver rustc <arguments>`.
        let driven = CargoClippy.compilerArguments(arguments, environment: environment)
        guard environment["TUIST_CARGO_CACHE_DIR"] != nil, let recorder = environment["TUIST_CARGO_RECORDER"],
              environment["TUIST_CARGO_INNER_WRAPPER"] == nil,
              CargoClippy.admitsWorkspaceWrapper(environment),
              let executable = (driven ?? arguments).first, URL(fileURLWithPath: executable).lastPathComponent == "rustc",
              !arguments.contains(where: {
                  $0.hasPrefix("@") || $0.hasPrefix("--print") || $0 == "--test" || $0 == "-o"
                      || $0.hasPrefix("--remap-path-prefix") || $0.hasPrefix("--sysroot") || $0.hasSuffix(".json")
                      || $0.hasPrefix("-Zincremental")
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
        var files: [String]
        var debugBundle: String?
        switch kind {
        case "lib", "rlib":
            // `cargo check` and `cargo clippy` emit metadata only; `--emit` is keyed with the other arguments.
            guard emitted == ["dep-info", "metadata", "link"] || emitted == ["dep-info", "metadata"] else { return nil }
            files = (emitted.contains("link") ? ["lib\(name)\(suffix).rlib"] : [])
                + ["lib\(name)\(suffix).rmeta", "\(name)\(suffix).d"]
        case "proc-macro":
            guard emitted == ["dep-info", "link"] else { return nil }
            #if os(macOS)
                files = ["lib\(name)\(suffix).dylib", "\(name)\(suffix).d"]
            #else
                files = ["lib\(name)\(suffix).so", "\(name)\(suffix).d"]
            #endif
        case "bin":
            // Linking reads every rlib of the dependency closure through `-L dependency=`, which the read set keys.
            // A build script's binary is stored before `CargoBuildScript` replaces it with a shim, and a hit installs one.
            guard emitted == ["dep-info", "link"] else { return nil }
            files = ["\(name)\(suffix)", "\(name)\(suffix).d"]
            #if os(macOS)
                if hasDebugMap(arguments) {
                    debugBundle = "\(name)\(suffix).dSYM"
                    files.insert(contentsOf: debugBundleFiles("\(name)\(suffix)"), at: 1)
                }
            #endif
        default:
            return nil
        }
        let identity = try await CargoToolchainIdentity.resolve(
            executable, environment: environment, directory: directory, process: process
        )
        guard identity.admitsLoader(environment) else { return nil }
        let relocation = CargoRelocation(environment: environment, sysroot: identity.sysroot)
        let inputHasher = CargoInputHasher(sessionDirectory: environment["TUIST_CARGO_SESSION"].map { URL(fileURLWithPath: $0) })
        let base = URL(fileURLWithPath: directory.pathString)
        var inputs = [
            keyVersion, CargoReadRecorder.version, directory.pathString, identity.version,
        ]
        var program = identity.sysroot.appendingPathComponent("bin/rustc").path
        if driven != nil {
            guard !emitted.contains("link"), let clippy = try await CargoClippy.prepare(
                arguments, sysroot: identity.sysroot, environment: environment, directory: directory, process: process
            ) else { return nil }
            program = clippy.driver.path
            inputs += try clippy.keyInputs(environment: environment, directory: directory, hasher: inputHasher)
        }
        inputs += CargoCacheInputs.keyArguments(Array(arguments.dropFirst()))
        // Package metadata the run reads is keyed with its reads.
        inputs += environment.sorted { $0.key < $1.key }.filter { CargoCacheInvocation.isKeyed($0.key) }
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
            // macOS's linker runs from protected programs the recorder cannot load into, so the declared key names it.
            // On Linux `cc`, `collect2` and `ld` load the recorder: the read set holds their binaries, CRT objects and
            // the C library they link against.
            #if os(macOS)
                inputs += try await CargoToolchainIdentity.linker(
                    environment: environment, directory: directory, process: process
                )
            #endif
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
        let encoded = try JSONEncoder().encode(inputs.map(relocation.relative))
        let declared = REAPI.digest(encoded)
        CargoCacheInvocation.trace(encoded, name: "\(name)-declared", digest: declared, environment: environment)
        return CargoRecordedInvocation(
            arguments: arguments, environment: environment, directory: directory,
            output: URL(fileURLWithPath: out, relativeTo: base).standardizedFileURL, name: name, files: files,
            key: declared, declared: declared, reads: nil, relocation: relocation, inputHasher: inputHasher,
            recorder: recorder, toolchain: identity.sysroot, externs: externs, linksWithSystemLinker: linksWithSystemLinker,
            debugBundle: debugBundle, program: program
        )
    }

    /// Whether a link's debug map names the objects lldb reads debug information from: ld64 writes their absolute
    /// paths, so a binary restored into another checkout, or after `cargo clean`, names objects that are elsewhere or
    /// gone. Cargo's macOS default leaves debug information unpacked in the objects; packed debug information has
    /// rustc run `dsymutil` itself, which recording does not admit, and a stripped binary has no debug map.
    /// Options are read as rustc reads them: `-C`, `-Cx` and `--codegen`, `-` and `_` alike in names, the last value
    /// winning, and `-g` as `-C debuginfo=2`.
    static func hasDebugMap(_ arguments: [String]) -> Bool {
        var options: [String: String] = [:]
        for (index, argument) in arguments.enumerated() {
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            let codegen = argument == "-C" || argument == "--codegen" ? next
                : argument.hasPrefix("--codegen=") ? String(argument.dropFirst(10))
                : argument.hasPrefix("-C") ? String(argument.dropFirst(2)) : nil
            if argument == "-g" { options["debuginfo"] = "2" }
            guard let parts = codegen?.split(separator: "=", maxSplits: 1), parts.count == 2 else { continue }
            options[parts[0].replacingOccurrences(of: "-", with: "_")] = String(parts[1])
        }
        return !["0", "none"].contains(options["debuginfo"] ?? "0") && options["split_debuginfo"] == "unpacked"
            && !["debuginfo", "symbols"].contains(options["strip"] ?? "none")
    }

    /// The files of a binary's `.dSYM` that lldb reads. `dsymutil` also writes a relocation map, which it alone uses.
    static func debugBundleFiles(_ binary: String) -> [String] {
        ["\(binary).dSYM/Contents/Info.plist", "\(binary).dSYM/Contents/Resources/DWARF/\(binary)"]
    }

    /// Writes the `.dSYM` of a linked binary that has a debug map, while the objects it names still exist, so the
    /// binary is stored and restored with debug information that does not depend on them. lldb prefers a
    /// UUID-matched `.dSYM` beside a binary over its debug map. `dsymutil` comes with the linker the declared key
    /// already identifies. `false` when it could not.
    ///
    /// An earlier build's bundle is overwritten in place, never removed first: Cargo uplifts it (links it beside the
    /// binary in the profile) as soon as it hears the compiler exit, which is when this runs, and a bundle that
    /// disappears between its existence and directory checks fails the build.
    func bundleDebugInformation(process: CargoProcess) async -> Bool {
        guard let debugBundle, let binary = files.first, let directory = try? AbsolutePath(validating: output.path)
        else { return true }
        let bundle = output.appendingPathComponent(debugBundle)
        // The parallel DWARF linker bundles a binary such as Codex's 1 GB `codex` in about half the time, with the same
        // functions, inlined calls, line tables and located variables. Toolchains without it get the classic one.
        var linked = false
        for linker in [["--linker", "parallel"], []] where !linked {
            // From the output directory, by name: the relocation map records the binary's path as given.
            linked = (try? await process.captureOutput(
                "/usr/bin/xcrun", arguments: ["dsymutil"] + linker + [binary, "-o", debugBundle], environment: environment,
                directory: directory
            )) != nil
        }
        guard linked else {
            try? FileManager.default.removeItem(at: bundle)
            return false
        }
        return Self.debugBundleFiles(binary)
            .allSatisfy { FileManager.default.fileExists(atPath: output.appendingPathComponent($0).path) }
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
        let encoded = try JSONEncoder().encode([declared.hash] + state)
        let digest = REAPI.digest(encoded)
        CargoCacheInvocation.trace(encoded, name: "\(name)-recorded", digest: digest, environment: environment)
        return digest
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

    /// The inputs of a finished, successful recorded compilation, or `nil` when it cannot be cached, with the reason
    /// passed to `explain`.
    func recorded(log: URL, started: Date, explain: (String) -> Void = { _ in }) -> CargoRecordedInvocation? {
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
            // rustc's incremental session holds only scratch state for its next compilation of this crate.
            allowedWrites: [output.path] + temporary
                + [CargoCacheInputs.incrementalDirectory(arguments, directory: directory)?.path].compactMap { $0 },
            allowedSpawn: { [linksWithSystemLinker] path in
                #if os(macOS)
                    guard linksWithSystemLinker else { return false }
                    let program = URL(fileURLWithPath: path).lastPathComponent
                    // rustc finds the SDK with `xcrun` and links with `cc`; both are keyed by `CargoToolchainIdentity.linker`.
                    return ["cc", "xcrun"].contains(program) || program == linker
                #else
                    // On Linux every program the link starts must load the recorder.
                    _ = (path, linker, linksWithSystemLinker)
                    return false
                #endif
            },
            keyedEnvironment: CargoCacheInvocation.isKeyed,
            explain: explain
        ),
            let depInfo = try? String(contentsOf: output.appendingPathComponent(files.last!), encoding: .utf8)
        else { return nil }
        reads.addEnvironmentDependencies(depInfo, keyedEnvironment: CargoCacheInvocation.isKeyed)
        if let changed = reads.changedInput(since: started, relocation: relocation) {
            explain("read \(changed), which changed while it ran")
            return nil
        }
        // Outputs that name a root behave the same only at that root, so their key names it too.
        for file in (try? outputFiles()) ?? [] where !file.hasSuffix(".d") && !file.contains("/") {
            guard let roots = try? relocation.boundRoots(of: output.appendingPathComponent(file)) else {
                explain("could not read its output \(file)")
                return nil
            }
            reads.bind(roots)
        }
        return with(reads)
    }

    static func isVolatile(_ name: String) -> Bool {
        CargoCacheInvocation.ignoredEnvironment.contains(name)
            || CargoCacheInvocation.ignoredEnvironmentPrefixes.contains(where: name.hasPrefix)
            // compiler-rt marks its profiling runtime as initialized for an instrumented process's children.
            || ["PWD", "TMPDIR", "NUM_JOBS", "__LLVM_PROFILE_RT_INIT_ONCE"].contains(name)
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
        let additional = try CargoCacheInputs.entries(of: output, prefix: String(files.last!.dropLast(2)) + ".")
            .filter { !files.contains($0) && acceptsOutput($0) }.sorted()
        guard files.count + additional.count <= CargoCompilationCache.maximumOutputFiles
        else { throw CargoCacheInvocation.CacheError.unsupported }
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

    /// Whether the dynamic loader settings in `environment` leave caching on. Cargo sets `LD_LIBRARY_PATH` for every
    /// process it starts: directories in the target (a unit's or the profile's `deps`, native search paths printed
    /// inside it), then what it inherited, which rustup's proxy starts with the toolchain's `lib`; empty when
    /// there is nothing to add. Those hold the toolchain's libraries and the build's own outputs. Any other loader
    /// setting, such as another search directory, `LD_PRELOAD`, `LD_AUDIT` or `DYLD_*`, can inject code or reads that
    /// hashing its value cannot cover. Paths compare resolved, as the loader opens them: rustup names a linked
    /// toolchain through its link, and an entry inside the target can link elsewhere.
    func admitsLoader(_ environment: [String: String]) -> Bool {
        func resolved(_ path: String) -> String {
            guard let real = realpath(path, nil) else { return URL(fileURLWithPath: path).standardizedFileURL.path }
            defer { free(real) }
            return String(cString: real)
        }
        let toolchain = [sysroot.appendingPathComponent("lib").path, targetLibdirPath].map(resolved)
        let target = environment["TUIST_CARGO_TARGET_DIR"].map { resolved($0) + "/" }
        return environment.allSatisfy { name, value in
            guard name.hasPrefix("LD_") || name.hasPrefix("DYLD_") else { return true }
            // glibc separates entries with `:` or `;`. An empty value searches nothing, but an empty entry in a list
            // searches the working directory.
            return name == "LD_LIBRARY_PATH" && (value.isEmpty || value.split(
                omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == ";" }
            ).allSatisfy { entry in
                guard entry.hasPrefix("/") else { return false }
                let path = resolved(String(entry))
                return toolchain.contains(path) || target.map { (path + "/").hasPrefix($0) } == true
            })
        }
    }

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
        let selection = persistentSelection(executable, environment: environment)
        let persistent = selection == nil ? nil : environment["TUIST_CARGO_CACHE_DIR"].map {
            URL(fileURLWithPath: $0).appendingPathComponent("toolchain/identity-" + REAPI.digest(Data(executable.utf8)).hash)
        }
        if let persistent, let selection, let data = try? Data(contentsOf: persistent),
           let stored = try? JSONDecoder().decode(PersistentIdentity.self, from: data), stored.selection == selection,
           let compiler = stored.identity.compilerPaths.first,
           (try? CargoInputHasher.identity(URL(fileURLWithPath: compiler)))?.fields == stored.compiler
        {
            if let named, let data = try? JSONEncoder().encode(stored.identity) { try? data.write(to: named, options: .atomic) }
            return stored.identity
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
        if let persistent, let selection, let fields = try? CargoInputHasher.identity(URL(fileURLWithPath: compilers[0])).fields,
           let data = try? JSONEncoder().encode(PersistentIdentity(selection: selection, identity: identity, compiler: fields))
        {
            try? FileManager.default.createDirectory(
                at: persistent.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: persistent, options: .atomic)
        }
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

    private struct PersistentIdentity: Codable {
        let selection: [String]
        let identity: CargoToolchainIdentity
        /// The identity of the compiler that answered `-vV`: a reinstalled toolchain asks again.
        let compiler: [String]
    }

    /// What selects the toolchain a compiler name answers for, so its answers persist across sessions like the
    /// linker's: the name, the pinned rustup toolchain and its directory, and the program `PATH` finds for the name.
    /// Without a pinned toolchain a rustup proxy also reads directory overrides, so those sessions probe.
    private static func persistentSelection(_ executable: String, environment: [String: String]) -> [String]? {
        guard let pinned = environment["RUSTUP_TOOLCHAIN"], !pinned.isEmpty, !pinned.contains("/") else { return nil }
        let program = executable.contains("/") ? executable : (environment["PATH"] ?? "").split(separator: ":")
            .map { String($0) + "/" + executable }.first { FileManager.default.isExecutableFile(atPath: $0) }
        let home = environment["RUSTUP_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rustup").path
        func status(_ path: String) -> String? {
            var value = stat()
            guard lstat(path, &value) == 0 else { return nil }
            #if os(Linux)
                let (modified, changed) = (value.st_mtim, value.st_ctim)
            #else
                let (modified, changed) = (value.st_mtimespec, value.st_ctimespec)
            #endif
            return "\(value.st_dev):\(value.st_ino):\(value.st_mode):\(value.st_size):\(modified.tv_sec):\(modified.tv_nsec):"
                + "\(changed.tv_sec):\(changed.tv_nsec)"
        }
        guard let program, case let resolved = URL(fileURLWithPath: program).resolvingSymlinksInPath().path,
              let programStatus = status(resolved), let toolchain = status("\(home)/toolchains/\(pinned)")
        else { return nil }
        return [executable, pinned, home, program, resolved, programStatus, toolchain]
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
                #if os(Linux)
                    let modified = info.st_mtim
                #else
                    let modified = info.st_mtimespec
                #endif
                identities.append("\(path):\(info.st_dev):\(info.st_ino):\(info.st_size):\(modified.tv_sec):\(modified.tv_nsec)")
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
