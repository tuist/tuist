import Foundation
import Path
import TuistREAPI

struct CargoCacheInvocation: CargoCacheAction {
    let arguments: [String]
    let environment: [String: String]
    let directory: AbsolutePath
    let package: URL
    let compiler: URL
    let launcher: URL
    let toolchain: URL
    /// `lib/rustlib/<host>` in the toolchain. Other installed targets and `rust-src` cannot affect host library builds.
    let hostTarget: URL
    let output: URL
    let name: String
    let files: [String]
    var key: REAPI.Digest
    let inputHasher: CargoInputHasher
    var compilerInputs: CargoCacheInputs?
    let relocation: CargoRelocation
    /// Selects the source list of an earlier compilation with the same arguments, environment, externs and root
    /// source, so its sources are hashed without running rustc to discover them. `nil` for registry leaves.
    var sourceIndex: CargoReadIndex?
    /// Sources must predate this moment to key a compilation found from rustc's own dep-info.
    var prepared = Date()

    /// No remembered source list: the compilation runs first and is keyed afterwards from the dep-info rustc writes
    /// anyway, instead of a separate discovery run of rustc.
    var isDeferred: Bool { compilerInputs?.sources.isEmpty == true }

    static let keyVersion = "tuist-swift-cargo-cache-v6"
    var cacheVersion: String { Self.keyVersion }
    var kind: String { "rust" }
    static let ignoredEnvironment = Set([
        "RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WRAPPER", "CARGO_MAKEFLAGS", "MAKEFLAGS", "MFLAGS", "CI",
        "SHLVL", "OLDPWD", "_", "TERM_SESSION_ID", "INVOCATION_ID",
    ])
    static let ignoredEnvironmentPrefixes = [
        "TUIST_", "GITHUB_", "GITLAB_", "BUILDKITE_", "CIRCLE_", "CI_", "RUNNER_", "ACTIONS_", "TRAVIS_", "TEAMCITY_",
    ]

    static func prepare(
        _ arguments: [String], environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws -> CargoCacheInvocation? {
        guard environment["TUIST_CARGO_CACHE_DIR"] != nil,
              environment["TUIST_CARGO_INNER_WRAPPER"] == nil,
              environment["RUSTC_WORKSPACE_WRAPPER"].map(\.isEmpty) ?? true,
              !environment.keys.contains(where: { $0.hasPrefix("LD_") || $0.hasPrefix("DYLD_") }),
              !arguments.contains(where: { argument in
                  argument.hasPrefix("-") && !argument.hasPrefix("--") && argument.count > 2
                      && !["-C", "-L", "-A", "-W", "-D", "-F"].contains(where: argument.hasPrefix)
              }),
              !arguments.contains(where: {
                  $0.hasPrefix("@") || $0.hasPrefix("-Z")
                      || $0.hasPrefix("--print") || $0.hasPrefix("--remap-path-prefix")
                      || $0.hasPrefix("--sysroot") || $0.hasPrefix("--target")
                      || $0.hasPrefix("--codegen") || $0.hasPrefix("--library-path")
                      || $0.hasPrefix("-l") || $0.hasPrefix("-o") || $0 == "--test"
              }),
              let executable = arguments.first, URL(fileURLWithPath: executable).lastPathComponent == "rustc",
              let manifest = environment["CARGO_MANIFEST_DIR"],
              let name = option("--crate-name", in: arguments),
              let kind = option("--crate-type", in: arguments), ["lib", "rlib"].contains(kind),
              let emit = option("--emit", in: arguments),
              Set(emit.split(separator: ",").map(String.init)) == Set(["dep-info", "metadata", "link"]),
              let out = option("--out-dir", in: arguments),
              let source = arguments.dropFirst().first(where: { $0.hasSuffix(".rs") }),
              !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
        else { return nil }
        let searches = arguments.enumerated().compactMap { index, value -> String? in
            if value == "-L", index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix("-L") ? String(value.dropFirst(2)) : nil
        }
        guard searches.allSatisfy({ $0.hasPrefix("dependency=") }) else { return nil }
        let codegen = arguments.enumerated().compactMap { index, value -> String? in
            if value == "-C", index + 1 < arguments.count { return arguments[index + 1] }
            return value.hasPrefix("-C") ? String(value.dropFirst(2)) : nil
        }
        let allowed = Set([
            "embed-bitcode", "debuginfo", "metadata", "extra-filename", "opt-level", "debug-assertions",
            "overflow-checks", "codegen-units", "panic", "strip", "target-cpu", "target-feature", "split-debuginfo",
        ])
        guard codegen.allSatisfy({ allowed.contains(String($0.prefix { $0 != "=" })) && $0 != "target-cpu=native" })
        else { return nil }
        if let split = codegen.last(where: { $0.hasPrefix("split-debuginfo=") }),
           !["split-debuginfo=off", "split-debuginfo=unpacked"].contains(split) { return nil }
        let suffix = codegen.first(where: { $0.hasPrefix("extra-filename=") }).map { String($0.dropFirst(15)) } ?? ""
        guard suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        let package = URL(fileURLWithPath: manifest).standardizedFileURL
        let cargoHome = URL(fileURLWithPath: environment["CARGO_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cargo").path)
        let registry = cargoHome.appendingPathComponent("registry/src").standardizedFileURL
        guard CargoCacheInputs.values("--extern", in: arguments).allSatisfy({
            let parts = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 && ["rlib", "rmeta"].contains(URL(fileURLWithPath: String(parts[1])).pathExtension)
        }) else { throw CacheError.unsupported }
        let inputHasher = CargoInputHasher(sessionDirectory: environment["TUIST_CARGO_SESSION"]
            .map { URL(fileURLWithPath: $0) })
        let externs = try CargoCacheInputs.resolveExterns(
            arguments: arguments, environment: environment, directory: directory, inputHasher: inputHasher
        )
        // Once per Cargo command: the toolchain cannot change under a running build.
        let identity = try await CargoToolchainIdentity.resolve(
            executable, environment: environment, directory: directory, process: process
        )
        let paths = [identity.sysrootPath, identity.targetLibdirPath]
        let toolchain = URL(fileURLWithPath: paths[0]).standardizedFileURL
        let hostTarget = URL(fileURLWithPath: paths[1]).standardizedFileURL.deletingLastPathComponent()
        guard hostTarget.deletingLastPathComponent() == toolchain.appendingPathComponent("lib/rustlib"),
              hostTarget.appendingPathComponent("lib") == URL(fileURLWithPath: paths[1]).standardizedFileURL
        else { return nil }
        let compiler = toolchain.appendingPathComponent("bin/rustc")
        guard let launcher = resolve(executable, environment: environment, directory: directory) else { return nil }
        if launcher != compiler.resolvingSymlinksInPath() {
            guard environment["RUSTUP_TOOLCHAIN"].map({ !$0.isEmpty }) == true,
                  launcher == resolve("rustup", environment: environment, directory: directory) else { return nil }
        }
        let files = ["lib\(name)\(suffix).rlib", "lib\(name)\(suffix).rmeta", "\(name)\(suffix).d"]
        var candidate = CargoCacheInvocation(
            arguments: arguments, environment: environment, directory: directory, package: package,
            compiler: compiler, launcher: launcher, toolchain: toolchain, hostTarget: hostTarget,
            output: URL(fileURLWithPath: out).standardizedFileURL,
            name: name, files: files, key: REAPI.emptyBlob,
            inputHasher: inputHasher,
            compilerInputs: nil,
            relocation: CargoRelocation(environment: environment, sysroot: toolchain)
        )
        if environment["OUT_DIR"] == nil,
           CargoCacheInputs.values("--extern", in: arguments).isEmpty,
           searches.allSatisfy({ $0.hasPrefix("dependency=") }),
           package.deletingLastPathComponent().deletingLastPathComponent() == registry,
           URL(fileURLWithPath: source, relativeTo: URL(fileURLWithPath: directory.pathString)).standardizedFileURL.path
           .hasPrefix(package.path + "/"),
           let key = try? candidate.fingerprint()
        {
            candidate.key = key
            return candidate
        }
        let rootSource = URL(fileURLWithPath: source, relativeTo: URL(fileURLWithPath: directory.pathString))
            .standardizedFileURL
        let rootDigest = try candidate.inputHasher.sourceDigest(rootSource, validate: validateSource)
        if let cache = environment["TUIST_CARGO_CACHE_DIR"] {
            var declared = [Self.keyVersion, "sources", directory.pathString, rootSource.path, rootDigest.hash]
            declared += candidate.keyArguments
            declared += environment.sorted { $0.key < $1.key }.filter { !Self.isIgnored($0.key) }.map { "\($0.key)=\($0.value)" }
            for file in externs {
                let digest = try inputHasher.digest(file, shared: true)
                declared += [file.path, digest.hash]
            }
            let digest = REAPI.digest(try JSONEncoder().encode(declared.map(candidate.relocation.relative)))
            candidate.sourceIndex = CargoReadIndex(
                root: URL(fileURLWithPath: cache),
                declaredKey: digest,
                version: Self.keyVersion,
                environment: environment
            )
        }
        if candidate.sourceIndex != nil {
            // Deferred until a source list is found, here or in `CargoCompilerObserver` from the remote cache.
            candidate.compilerInputs = CargoCacheInputs(sources: [], externs: externs)
            if let listed = await candidate.sourceIndex?.get(remote: nil),
               let keyed = try candidate.keyed(sources: listed) { return keyed }
            return candidate
        }
        // Without a cache directory there is nowhere to remember sources: discover them now.
        candidate.compilerInputs = try await CargoCacheInputs.discover(
            arguments: arguments, environment: environment, directory: directory,
            externs: externs, process: process
        )
        candidate.key = try candidate.fingerprint()
        return candidate
    }

    /// This compilation keyed by a remembered source list, or `nil` when one of its files no longer exists.
    func keyed(sources listed: CargoReadSet) throws -> CargoCacheInvocation? {
        let sources = listed.entries.filter { $0.kind == "path" }.compactMap { relocation.absolute($0.name) }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard !sources.isEmpty, sources.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        var keyed = self
        guard let externs = compilerInputs?.externs else { return nil }
        keyed.compilerInputs = CargoCacheInputs(sources: Set(sources).sorted { $0.path < $1.path }, externs: externs)
        keyed.key = try keyed.fingerprint()
        return keyed
    }

    /// The sources rustc's dep-info names for this compilation, once rustc has written it (before its metadata).
    private func depInfoSources() -> [URL]? {
        let path = output.appendingPathComponent(files[2])
        guard (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ $0 }).map({ $0 < 2_000_000 }) == true,
              let text = try? String(contentsOf: path, encoding: .utf8), let dependencies = try? Self.dependencies(text)
        else { return nil }
        let base = URL(fileURLWithPath: directory.pathString)
        let sources = Set(dependencies.map { URL(fileURLWithPath: $0, relativeTo: base).standardizedFileURL })
        guard !sources.isEmpty, sources.count <= 10000 else { return nil }
        return sources.sorted { $0.path < $1.path }
    }

    /// This compilation keyed by rustc's dep-info, provided every source predates `prepared`: a file changed while
    /// rustc read it would key new content with old output. Admission scans each source as it is hashed.
    func keyedFromDepInfo() -> CargoCacheInvocation? {
        guard let sources = depInfoSources() else { return nil }
        let limit = prepared.timeIntervalSince1970
        guard sources.allSatisfy({ file in
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .attributeModificationDateKey]),
                  let modified = values.contentModificationDate, let changed = values.attributeModificationDate
            else { return false }
            return max(modified, changed).timeIntervalSince1970 < limit
        }) else { return nil }
        guard let externs = compilerInputs?.externs else { return nil }
        var keyed = self
        keyed.compilerInputs = CargoCacheInputs(sources: sources, externs: externs)
        guard let key = try? keyed.fingerprint() else { return nil }
        keyed.key = key
        return keyed
    }

    /// After a successful compilation, remembers the sources rustc actually read (a deferred compilation's first list,
    /// or a new one after a module was added or removed) and returns the compilation keyed by them. `self` when the
    /// remembered list was right; `nil` when the compilation cannot be keyed.
    func refreshed(remote: (any REAPICacheStoring)?) async -> CargoCacheInvocation? {
        guard let sourceIndex else { return self }
        guard let sources = depInfoSources() else { return nil }
        guard sources != compilerInputs?.sources else { return self }
        let set = CargoReadSet(entries: sources.map { CargoReadSet.Entry(kind: "path", name: relocation.relative($0.path)) })
        await sourceIndex.put(set, remote: remote, environment: environment)
        return keyedFromDepInfo()
    }

    func fingerprint() throws -> REAPI.Digest {
        var inputs = [Self.keyVersion, directory.pathString]
        inputs += keyArguments
        inputs += environment.sorted { $0.key < $1.key }.filter { !Self.isIgnored($0.key) }.map { "\($0.key)=\($0.value)" }
        var budget = 2_000_000_000
        if let compilerInputs {
            for file in compilerInputs.sources {
                let digest = try inputHasher.sourceDigest(file, validate: Self.validateSource)
                inputs += [file.path, digest.hash, String(digest.sizeBytes)]
            }
            // A remembered source list cannot see a file that would now change module resolution, such as a new
            // `foo/mod.rs` beside `foo.rs`: the directories holding the sources are keyed by their entries.
            for parent in Set(compilerInputs.sources.map { $0.deletingLastPathComponent().path }).sorted() {
                let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent))?.sorted() ?? []
                inputs += [parent + "/", entries.joined(separator: "\u{0}")]
            }
            for file in compilerInputs.externs {
                let digest = try inputHasher.digest(file, shared: true)
                try CargoCacheInputs.validateDependency(file, digest: digest, environment: environment)
                inputs += [file.path, digest.hash, String(digest.sizeBytes)]
            }
        } else {
            inputs += try snapshot(package, budget: &budget, inspectSources: true)
        }
        let libraries = toolchain.appendingPathComponent("lib")
        inputs += try inputHasher.withSharedDigests(under: libraries) {
            // The compiler's own libraries, then the host target's standard library and runtime support.
            // Its `bin` directory only serves linking, which library compilations never perform.
            try snapshot(libraries, budget: &budget, recursive: false)
                + snapshot(hostTarget, budget: &budget, excluding: "bin")
        }
        for executable in Set([compiler.resolvingSymlinksInPath(), launcher]).sorted(by: { $0.path < $1.path }) {
            let digest = try inputHasher.digest(executable, shared: true)
            inputs += [executable.path, digest.hash, String(digest.sizeBytes)]
        }
        // Every path is keyed relative to its root; the compilation itself runs with matching remaps.
        inputs.append(relocation.remapArguments.map(relocation.relative).joined(separator: " "))
        let encoded = try JSONEncoder().encode(inputs.map(relocation.relative))
        let digest = REAPI.digest(encoded)
        // Like blaze's `BLAZE_KEY_TRACE`: every key's inputs, so two builds' misses can be diffed.
        if let trace = environment["TUIST_CARGO_KEY_TRACE"], !trace.isEmpty {
            try? FileManager.default.createDirectory(atPath: trace, withIntermediateDirectories: true)
            try? encoded.write(to: URL(fileURLWithPath: trace).appendingPathComponent("\(name)-\(digest.hash.prefix(12)).json"))
        }
        return digest
    }

    var remapArguments: [String] { relocation.remapArguments }

    func storedOutput(_ data: Data) -> Data? { relocation.relative(data) }

    func unkeyedRoots(in data: Data) -> [String] { relocation.boundRoots(in: data).map(\.path) }

    func restoredOutput(_ data: Data) -> Data? { relocation.absolute(data) }

    func acceptsOutput(_ file: String) -> Bool {
        if files.contains(file) { return true }
        let prefix = String(files[2].dropLast(2)) + "."
        return file.hasPrefix(prefix) && ["o", "dwo", "dwp"].contains(URL(fileURLWithPath: file).pathExtension)
            && file.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    func outputFiles() throws -> [String] {
        let additional = try FileManager.default.contentsOfDirectory(atPath: output.path)
            .filter { !files.contains($0) && acceptsOutput($0) }.sorted()
        guard files.count + additional.count <= 128 else { throw CacheError.unsupported }
        return files + additional
    }

    var keyArguments: [String] {
        var result: [String] = []
        var seen = false
        var index = 0
        while index < arguments.count {
            let parts = arguments[index].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let option = parts.first ?? ""
            guard option == "--diagnostic-width" else {
                result.append(arguments[index]); index += 1; continue
            }
            let value = parts.count == 2 ? parts[1] : (index + 1 < arguments.count ? arguments[index + 1] : "")
            guard !seen, !value.hasPrefix("-"), let width = Int(value, radix: 10), width >= 0 else { return arguments }
            seen = true
            index += parts.count == 2 ? 1 : 2
        }
        return result
    }

    func validateDependencies() throws {
        let path = output.appendingPathComponent(files[2])
        guard (try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 2_000_000 else {
            throw CacheError.unsupported
        }
        let text = try String(contentsOf: path, encoding: .utf8)
        try Self.validateEnvironmentDependencies(text)
        let dependencies = try Self.dependencies(text)
        if let compilerInputs {
            let sources = Set(dependencies.map {
                URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: directory.pathString)).standardizedFileURL
            })
            guard sources == Set(compilerInputs.sources) else { throw CacheError.unsupported }
            return
        }
        guard !dependencies.isEmpty, dependencies.allSatisfy({ dependency in
            let file = URL(fileURLWithPath: dependency, relativeTo: URL(fileURLWithPath: directory.pathString))
                .standardizedFileURL
            return file.path.hasPrefix(package.path + "/")
        }) else { throw CacheError.unsupported }
    }

    func validateDependencies(restoring: Bool) async throws {
        if !restoring { try validateDependencies() }
    }

    func certifyOutputs(metadataOnly: Bool = false) throws {
        if isDeferred {
            // Keyed just now from the same dep-info: checking that key again would compute it a second time.
            guard let keyed = keyedFromDepInfo() else { throw CacheError.unsupported }
            try keyed.validateDependencies()
            return try keyed.certify(metadataOnly: metadataOnly)
        }
        try validateDependencies()
        guard try fingerprint() == key else { throw CacheError.unsupported }
        try certify(metadataOnly: metadataOnly)
    }

    func certifyCheckedOutputs() throws {
        guard !isDeferred else { return try certifyOutputs(metadataOnly: false) }
        try certify(metadataOnly: false)
    }

    private func certify(metadataOnly: Bool) throws {
        for name in metadataOnly ? [files[1]] : Array(files.prefix(2)) {
            let digest = try inputHasher.digest(output.appendingPathComponent(name), shared: true)
            guard let proof = CargoCacheInputs.proofPath(digest, environment: environment) else { continue }
            try FileManager.default.createDirectory(at: proof.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Self.keyVersion.utf8).write(to: proof, options: .atomic)
        }
    }

    static func validateEnvironmentDependencies(_ text: String) throws {
        guard !text.split(separator: "\n").contains(where: { line in
            guard line.hasPrefix("# env-dep:") else { return false }
            return isIgnored(String(line.dropFirst(10).prefix { $0 != "=" }))
        }) else { throw CacheError.unsupported }
    }

    static func dependencies(_ text: String) throws -> [String] {
        var result: [String] = []
        for line in text.replacingOccurrences(of: "\\\n", with: " ").split(separator: "\n") where !line.hasPrefix("#") {
            var escaped = false
            var separator: String.SubSequence.Index?
            for index in line.indices {
                let character = line[index]
                if !escaped, character == ":" { separator = index; break }
                escaped = !escaped && character == "\\"
            }
            guard let separator else { throw CacheError.unsupported }
            var token = ""
            escaped = false
            for character in line[line.index(after: separator)...] {
                if escaped {
                    token.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character.isWhitespace {
                    if !token.isEmpty { result.append(token); token = "" }
                } else {
                    token.append(character)
                }
            }
            guard !escaped else { throw CacheError.unsupported }
            if !token.isEmpty { result.append(token) }
        }
        return result
    }

    private func snapshot(
        _ root: URL, budget: inout Int, inspectSources: Bool = false, recursive: Bool = true, excluding: String? = nil
    ) throws -> [String] {
        var failed = false
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let entries = FileManager.default.enumerator(
                  at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                  options: recursive ? [] : [.skipsSubdirectoryDescendants],
                  errorHandler: { _, _ in failed = true; return false }
              ) else { throw CacheError.unsupported }
        var files: [(file: URL, digest: REAPI.Digest)] = []
        for case let file as URL in entries {
            let properties = try file.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            if properties.isDirectory == true, file.lastPathComponent == excluding,
               file.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
            {
                entries.skipDescendants()
                continue
            }
            if properties.isSymbolicLink == true {
                let target = file.resolvingSymlinksInPath()
                guard !inspectSources, target.path.hasPrefix(toolchain.path + "/"),
                      try target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                else {
                    throw CacheError.unsupported
                }
                files.append((target, try inputHasher.digest(target, shared: true)))
            }
            if properties.isDirectory == true { continue }
            let content = properties.isSymbolicLink == true ? file.resolvingSymlinksInPath() : file
            let regular = properties.isSymbolicLink == true
                ? try content.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) : properties
            guard files.count < 10000, regular.isRegularFile == true, let size = regular.fileSize,
                  size <= budget else { throw CacheError.unsupported }
            budget -= size
            let digest: REAPI.Digest
            if inspectSources, file.pathExtension == "rs" {
                guard size <= 2_000_000 else { throw CacheError.unsupported }
                digest = try inputHasher.sourceDigest(content) { data in
                    guard let text = Self.code(data), !Self.matches(Self.registryWords, text)
                    else { throw CacheError.unsupported }
                }
            } else {
                digest = try inputHasher.digest(content, shared: !inspectSources)
            }
            files.append((file, digest))
        }
        guard !failed else { throw CacheError.unsupported }
        return files.sorted { $0.file.path < $1.file.path }.flatMap {
            [$0.file.path, $0.digest.hash, String($0.digest.sizeBytes)]
        }
    }

    private static func resolve(_ executable: String, environment: [String: String], directory: AbsolutePath) -> URL? {
        let base = URL(fileURLWithPath: directory.pathString, isDirectory: true)
        let candidates = executable.contains("/") ? [URL(fileURLWithPath: executable, relativeTo: base)] :
            (environment["PATH"] ?? "").components(separatedBy: ":").map {
                URL(fileURLWithPath: $0.isEmpty ? "." : $0, relativeTo: base).appendingPathComponent(executable)
            }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })?
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Keys name only what rustc or the crate can read on purpose: Cargo's and rustc's own variables, deployment
    /// targets, and the SDK. The rest of the shell (`HOME`, `PATH`, `USER`, ...) differs between machines; a crate that
    /// reads one through `env!`/`option_env!` names it in dep-info and is never published.
    static func isIgnored(_ name: String) -> Bool {
        if ignoredEnvironment.contains(name) || ignoredEnvironmentPrefixes.contains(where: name.hasPrefix) { return true }
        let keyed = ["CARGO_", "RUSTC_", "RUST_"].contains(where: name.hasPrefix)
            || ["CARGO", "RUSTC", "RUSTFLAGS", "RUSTDOCFLAGS", "OUT_DIR", "SDKROOT", "RUSTUP_TOOLCHAIN"].contains(name)
            || name.hasSuffix("_DEPLOYMENT_TARGET")
        return !keyed
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        if let index = arguments.firstIndex(of: name), index + 1 < arguments.count { return arguments[index + 1] }
        return arguments.first(where: { $0.hasPrefix(name + "=") }).map { String($0.dropFirst(name.count + 1)) }
    }

    enum CacheError: Error { case unsupported }
}

extension CargoCacheInvocation {
    private static let sourceWords = [
        "asm", "global_asm", "naked_asm", "link", "link_args", "concat_idents", "macro_metavar_expr_concat", "concat",
    ].map { Array($0.utf8) }

    /// Non-ASCII bytes conservatively delimit candidates; the regex still decides Unicode boundaries and whitespace.
    private static func hasSourceWord(_ data: Data) -> Bool {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Bool in
            func isWord(_ byte: UInt8) -> Bool {
                (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 95
            }
            var index = 0
            while index < bytes.count {
                guard isWord(bytes[index]) else { index += 1; continue }
                let start = index
                repeat {
                    index += 1
                } while index < bytes.count && isWord(bytes[index])
                let word = bytes[start ..< index]
                if sourceWords.contains(where: { $0.count == word.count && word.elementsEqual($0) }) {
                    return true
                }
            }
            return false
        }
    }

    private static func validateSource(_ data: Data) throws {
        guard hasSourceWord(data) else { return }
        guard let code = code(data), !matches(sourceTokens, code) else { throw CacheError.unsupported }
    }

    /// Compiled once: `String.range(of:options: .regularExpression)` compiles the same ICU expression on every call,
    /// which cost more than a second of a cold build's admission work. The engine and patterns are unchanged.
    private static let sourceTokens = try! NSRegularExpression(
        pattern: "\\b(asm|global_asm|naked_asm|link_args|concat_idents|macro_metavar_expr_concat)\\b|\\blink\\s*\\(|\\$\\s*\\{\\s*concat\\b"
    )
    private static let registryWords = try! NSRegularExpression(
        pattern: "\\b(asm|global_asm|naked_asm|link|link_args|extern|include|concat|concat_idents)\\b"
    )

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Rust source with comments and the contents of string, byte and character literals blanked, so admission
    /// matches tokens rather than prose such as "symbolic link" or a `"asm"` file-type name. Returns `nil` when the
    /// source does not lex, which callers treat as unsupported.
    static func code(_ data: Data) -> String? {
        var bytes = [UInt8](data)
        let count = bytes.count
        func isIdentifier(_ byte: UInt8) -> Bool {
            (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) || byte == 95 || byte >= 128
        }
        func blank(_ range: Range<Int>) {
            for index in range where bytes[index] != 10 {
                bytes[index] = 32
            }
        }
        var index = 0
        while index < count {
            let byte = bytes[index]
            let next = index + 1 < count ? bytes[index + 1] : 0
            if byte == 47, next == 47 { // line comment
                var end = index
                while end < count, bytes[end] != 10 {
                    end += 1
                }
                blank(index ..< end)
                index = end
            } else if byte == 47, next == 42 { // nested block comment
                var depth = 0
                var end = index
                repeat {
                    guard end + 1 < count else { return nil }
                    if bytes[end] == 47, bytes[end + 1] == 42 {
                        depth += 1
                        end += 2
                    } else if bytes[end] == 42, bytes[end + 1] == 47 {
                        depth -= 1
                        end += 2
                    } else {
                        end += 1
                    }
                } while depth > 0
                blank(index ..< end)
                index = end
            } else if byte == 114, index == 0 || !isIdentifier(bytes[index - 1]) || (
                index >= 1 && [98, 99].contains(bytes[index - 1]) && (index == 1 || !isIdentifier(bytes[index - 2]))
            ), next == 34 || next == 35 { // raw string: r"..", r#".."#, br.., cr..
                var hashes = 0
                var start = index + 1
                while start < count, bytes[start] == 35 {
                    hashes += 1; start += 1
                }
                guard start < count, bytes[start] == 34 else { index += 1; continue } // raw identifier
                var end = start + 1
                while true {
                    guard end < count else { return nil }
                    if bytes[end] == 34, end + hashes < count, bytes[(end + 1) ..< (end + 1 + hashes)].allSatisfy({ $0 == 35 }) {
                        break
                    }
                    end += 1
                }
                blank((start + 1) ..< end)
                index = end + 1 + hashes
            } else if byte == 34 { // string
                var end = index + 1
                while true {
                    guard end < count else { return nil }
                    if bytes[end] == 92 { end += 2; continue }
                    if bytes[end] == 34 { break }
                    end += 1
                }
                blank((index + 1) ..< end)
                index = end + 1
            } else if byte == 39 { // character literal or lifetime
                var end = index + 1
                if next == 92 {
                    end += 2
                    while end < count, end - index < 16, bytes[end] != 39 {
                        end += 1
                    }
                    guard end < count, bytes[end] == 39 else { return nil }
                } else {
                    guard end < count else { return nil }
                    let lead = bytes[end]
                    end += lead < 0x80 ? 1 : lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : 2
                    guard end < count, bytes[end] == 39 else { index += 1; continue } // lifetime or label
                }
                blank((index + 1) ..< end)
                index = end + 1
            } else {
                index += 1
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
