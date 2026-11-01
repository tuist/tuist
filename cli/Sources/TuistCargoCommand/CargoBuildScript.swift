import Foundation
import Path
import TuistProcess
import TuistREAPI

/// Build-script runs, kept as blaze keeps them: Cargo starts build scripts itself, so after a build script compiles,
/// its executable is replaced by a shim that hands the run to `tuist cargo __script` while a session provides one,
/// and runs the real script otherwise. The run is recorded; its outputs (`OUT_DIR`, the directives it printed) are
/// stored under a declared key (what the script was built from, its arguments and Cargo's variables, relocated) and the
/// current contents of what it read.
enum CargoBuildScript {
    static let version = "tuist-swift-cargo-script-v1"
    static let realSuffix = ".tuist-real"
    static let madeOfSuffix = ".tuist-made-of"
    static let maximumBytes: Int64 = 500_000_000

    // MARK: - Installation

    /// After a successful build-script compilation, records what it was built from and installs the shim.
    static func install(
        _ arguments: [String], environment: [String: String], directory: AbsolutePath, process: CargoProcess
    ) async throws {
        guard environment["TUIST_CARGO_SCRIPT"] != nil,
              CargoCacheInputs.values("--crate-name", in: arguments).first == "build_script_build",
              CargoCacheInputs.values("--crate-type", in: arguments) == ["bin"],
              let executable = arguments.first, let out = CargoCacheInputs.values("--out-dir", in: arguments).first
        else { return }
        let suffix = CargoCacheInputs.values("-C", in: arguments).first(where: { $0.hasPrefix("extra-filename=") })
            .map { String($0.dropFirst(15)) } ?? ""
        let base = URL(fileURLWithPath: directory.pathString)
        let outputDirectory = URL(fileURLWithPath: out, relativeTo: base).standardizedFileURL
        let binary = outputDirectory.appendingPathComponent("build_script_build\(suffix)")
        let depInfo = outputDirectory.appendingPathComponent("build_script_build\(suffix).d")
        guard FileManager.default.isExecutableFile(atPath: binary.path),
              let text = try? String(contentsOf: depInfo, encoding: .utf8)
        else { return }
        let identity = try await CargoToolchainIdentity.resolve(
            executable, environment: environment, directory: directory, process: process
        )
        let relocation = CargoRelocation(environment: environment, sysroot: identity.sysroot)
        let hasher = CargoInputHasher(sessionDirectory: environment["TUIST_CARGO_SESSION"].map { URL(fileURLWithPath: $0) })
        // The executable's bytes name the checkout and object timestamps, so a run is keyed by what it was built from.
        var inputs = [version, directory.pathString, identity.version]
        inputs += arguments.dropFirst().filter { !$0.hasPrefix("--diagnostic-width") }
        inputs += environment.sorted { $0.key < $1.key }.filter { !CargoCacheInvocation.isIgnored($0.key) }
            .map { "\($0.key)=\($0.value)" }
        for source in Set(try CargoCacheInvocation.dependencies(text)).sorted() {
            let file = URL(fileURLWithPath: source, relativeTo: base).standardizedFileURL
            let digest = try hasher.digest(file, shared: true)
            inputs += [file.path, digest.hash, String(digest.sizeBytes)]
        }
        for value in CargoCacheInputs.values("--extern", in: arguments) {
            let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let file = URL(fileURLWithPath: String(parts[1]), relativeTo: base).standardizedFileURL
            let digest = try hasher.digest(file, shared: true)
            inputs += [file.path, digest.hash, String(digest.sizeBytes)]
        }
        for compiler in identity.compilerFiles {
            let digest = try hasher.digest(compiler, shared: true)
            inputs += [compiler.path, digest.hash, String(digest.sizeBytes)]
        }
        #if os(macOS)
            inputs += try await CargoToolchainIdentity.linker(environment: environment, directory: directory, process: process)
        #endif
        let madeOf = REAPI.digest(try JSONEncoder().encode(inputs.map(relocation.relative))).hash
        let real = URL(fileURLWithPath: binary.path + realSuffix)
        let name = binary.lastPathComponent
        let shim = """
        #!/bin/sh
        real="$(dirname "$0")/\(name)\(realSuffix)"
        if [ -n "${TUIST_CARGO_SCRIPT-}" ]; then exec "$TUIST_CARGO_SCRIPT" cargo __script "$real" "$@"; fi
        exec "$real" "$@"

        """
        let temporary = outputDirectory.appendingPathComponent(".tuist-shim-" + UUID().uuidString)
        try Data(shim.utf8).write(to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        try Data(madeOf.utf8).write(to: URL(fileURLWithPath: binary.path + madeOfSuffix), options: .atomic)
        if FileManager.default.fileExists(atPath: real.path) { try FileManager.default.removeItem(at: real) }
        try FileManager.default.moveItem(at: binary, to: real)
        do {
            try FileManager.default.moveItem(at: temporary, to: binary)
        } catch {
            try? FileManager.default.moveItem(at: real, to: binary)
            throw error
        }
    }

    // MARK: - Running

    struct Outputs: Codable {
        struct File: Codable {
            let path: String
            let hash: String
            let size: Int64
            let executable: Bool
            /// Text stored with machine-specific roots replaced, given this machine's roots back when restored.
            let relocated: Bool

            var digest: REAPI.Digest { .with { $0.hash = hash; $0.sizeBytes = size } }
        }

        let stdout: File
        let stderr: File
        let directories: [String]
        let files: [File]
    }

    /// Runs the real build script at `real`, reusing an earlier run with the same inputs.
    static func run(
        real: String, arguments: [String], environment inherited: [String: String], directory: AbsolutePath,
        runner: CommandRunning
    ) async throws {
        var environment = inherited
        // The session's compiler wrapper starts unrecorded shells; probes that honor `RUSTC_WRAPPER` reach the same
        // compiler without it.
        if let wrapper = environment["RUSTC_WRAPPER"], let session = environment["TUIST_CARGO_SESSION"],
           wrapper.hasPrefix(session + "/") { environment["RUSTC_WRAPPER"] = nil }
        let process = CargoProcess(runner: runner)
        guard let context = try? await Context.make(
            real: real,
            arguments: arguments,
            environment: environment,
            directory: directory,
            process: process
        )
        else {
            try await process.execute(real, arguments: arguments, environment: environment, directory: directory)
            return
        }
        let remote = try? await CargoCompilerObserver.remote(environment)
        if let reads = await context.index.get(remote: remote),
           let key = try? context.key(reads),
           await context.restore(key: key, remote: remote)
        {
            context.debug("restored build-script run")
            return
        }
        let log = context.session.appendingPathComponent("reads-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let started = Date()
        var stdout = Data()
        var stderr = Data()
        var bounded = true
        for try await event in runner.run(
            // Started directly: `/usr/bin/env` is protected, and macOS drops `DYLD_*` when it starts.
            arguments: [URL(fileURLWithPath: real, relativeTo: URL(fileURLWithPath: directory.pathString)).path] + arguments,
            environment: CargoReadRecorder.environment(
                environment, library: context.recorder, log: log, toolchain: context.relocation.roots
                    .first(where: { $0.placeholder == "@@TUIST_SYSROOT@@" })?.path ?? ""
            ),
            workingDirectory: directory
        ) {
            switch event {
            case let .standardOutput(bytes):
                FileHandle.standardOutput.write(Data(bytes))
                if stdout.count + bytes.count <= 16_000_000 { stdout.append(contentsOf: bytes) } else { bounded = false }
            case let .standardError(bytes):
                FileHandle.standardError.write(Data(bytes))
                if stderr.count + bytes.count <= 16_000_000 { stderr.append(contentsOf: bytes) } else { bounded = false }
            }
        }
        guard bounded else { return }
        await context.store(log: log, started: started, stdout: stdout, stderr: stderr, remote: remote)
    }

    struct Context {
        let declared: REAPI.Digest
        let outDirectory: URL
        let environment: [String: String]
        let relocation: CargoRelocation
        let hasher: CargoInputHasher
        let root: URL
        let session: URL
        let recorder: String
        let index: CargoReadIndex

        static func make(
            real: String, arguments: [String], environment: [String: String], directory: AbsolutePath,
            process: CargoProcess
        ) async throws -> Context? {
            guard let cache = environment["TUIST_CARGO_CACHE_DIR"], let session = environment["TUIST_CARGO_SESSION"],
                  let recorder = environment["TUIST_CARGO_RECORDER"], let out = environment["OUT_DIR"],
                  !environment.keys.contains(where: { $0.hasPrefix("LD_") || $0.hasPrefix("DYLD_") }),
                  let madeOf = try? String(
                      contentsOfFile: String(real.dropLast(realSuffix.count)) + madeOfSuffix,
                      encoding: .utf8
                  ),
                  let rustc = environment["RUSTC"]
            else { return nil }
            let outDirectory = URL(fileURLWithPath: out).standardizedFileURL
            // A rerun finds the previous run's files, which it may read: only a fresh `OUT_DIR` is a known state.
            guard (try? FileManager.default.contentsOfDirectory(atPath: outDirectory.path))?.isEmpty ?? true else { return nil }
            let identity = try await CargoToolchainIdentity.resolve(
                rustc, environment: environment, directory: directory, process: process
            )
            let relocation = CargoRelocation(environment: environment, sysroot: identity.sysroot)
            var inputs = [version, CargoReadRecorder.version, madeOf, directory.pathString]
            inputs += arguments
            inputs += environment.sorted { $0.key < $1.key }.filter { isKeyed($0.key) }.map { "\($0.key)=\($0.value)" }
            let declared = REAPI.digest(try JSONEncoder().encode(inputs.map(relocation.relative)))
            let root = URL(fileURLWithPath: cache)
            return Context(
                declared: declared, outDirectory: outDirectory, environment: environment, relocation: relocation,
                hasher: CargoInputHasher(sessionDirectory: URL(fileURLWithPath: session)), root: root,
                session: URL(fileURLWithPath: session), recorder: recorder,
                index: CargoReadIndex(root: root, declaredKey: declared, version: version)
            )
        }

        /// What Cargo sets for a build script. The rest of the shell is keyed only when the script reads it.
        static func isKeyed(_ name: String) -> Bool {
            !CargoRecordedInvocation.isVolatile(name) && name != "RUSTC_WRAPPER"
                && ([
                    "CARGO",
                    "CARGO_",
                    "DEP_",
                    "RUSTC",
                    "RUSTDOC",
                    "TARGET",
                    "HOST",
                    "PROFILE",
                    "OPT_LEVEL",
                    "DEBUG",
                    "OUT_DIR",
                    "RUSTFLAGS",
                    "SDKROOT",
                ]
                .contains(where: { name == $0 || ($0.hasSuffix("_") && name.hasPrefix($0)) })
                || name.hasSuffix("_DEPLOYMENT_TARGET"))
        }

        func key(_ reads: CargoReadSet) throws -> REAPI.Digest {
            let state = try reads.evaluate(
                relocation: relocation, environment: environment, hasher: hasher,
                volatileEnvironment: { CargoRecordedInvocation.isVolatile($0) || $0 == "RUSTC_WRAPPER" }
            )
            return REAPI.digest(try JSONEncoder().encode([declared.hash] + state))
        }

        private func actionDigest(_ key: REAPI.Digest) -> (command: Data, action: Data, digest: REAPI.Digest)? {
            guard let command = try? REAPI.Command.with({ $0.arguments = [version, "run", key.hash, String(key.sizeBytes)] })
                .serializedData(),
                let action = try? REAPI.Action.with({
                    $0.commandDigest = REAPI.digest(command)
                    $0.inputRootDigest = REAPI.emptyBlob
                }).serializedData()
            else { return nil }
            return (command, action, REAPI.digest(action))
        }

        private func blobPath(_ digest: REAPI.Digest) -> URL { root.appendingPathComponent("blobs/" + digest.hash) }

        private func hasBlob(_ digest: REAPI.Digest) -> Bool {
            (try? REAPI.digest(file: blobPath(digest))) == digest
        }

        func restore(key: REAPI.Digest, remote: (any REAPICacheStoring)?) async -> Bool {
            guard let (_, _, action) = actionDigest(key) else { return false }
            let local = root.appendingPathComponent("script-actions/" + action.hash)
            var result = (try? Data(contentsOf: local)).flatMap { try? REAPI.ActionResult(serializedBytes: $0) }
            if result == nil, let remote { result = try? await remote.actionResult(for: action) }
            guard let result, result.exitCode == 0, let manifest = result.outputFiles.first, manifest.path == "outputs.json"
            else { return false }
            let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            guard await fetch([manifest.digest], into: staging, remote: remote),
                  let outputs = try? JSONDecoder().decode(Outputs.self, from: Data(contentsOf: blobPath(manifest.digest))),
                  outputs.files.allSatisfy({ isSafe($0.path) }), outputs.directories.allSatisfy(isSafe),
                  await fetch(
                      [outputs.stdout.digest, outputs.stderr.digest] + outputs.files.map(\.digest),
                      into: staging,
                      remote: remote
                  ),
                  let stdout = read(outputs.stdout), let stderr = read(outputs.stderr)
            else { return false }
            do {
                // Into a fresh sibling first, so an interrupted restoration never leaves a partial `OUT_DIR`.
                let next = outDirectory.deletingLastPathComponent().appendingPathComponent(".tuist-out-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: next) }
                try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
                for directory in outputs.directories {
                    try FileManager.default.createDirectory(
                        at: next.appendingPathComponent(directory),
                        withIntermediateDirectories: true
                    )
                }
                for file in outputs.files {
                    guard let data = read(file) else { return false }
                    let destination = next.appendingPathComponent(file.path)
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: destination)
                    try FileManager.default.setAttributes(
                        [.posixPermissions: file.executable ? 0o755 : 0o644], ofItemAtPath: destination.path
                    )
                }
                guard (try? FileManager.default.contentsOfDirectory(atPath: outDirectory.path))?.isEmpty ?? true
                else { return false }
                try? FileManager.default.removeItem(at: outDirectory)
                try FileManager.default.moveItem(at: next, to: outDirectory)
            } catch { return false }
            try? write(result.serializedData(), to: local)
            FileHandle.standardOutput.write(stdout)
            FileHandle.standardError.write(stderr)
            return true
        }

        private func read(_ file: Outputs.File) -> Data? {
            guard let data = try? Data(contentsOf: blobPath(file.digest)), REAPI.digest(data) == file.digest else { return nil }
            return file.relocated ? relocation.absolute(data) : data
        }

        private func fetch(_ digests: [REAPI.Digest], into staging: URL, remote: (any REAPICacheStoring)?) async -> Bool {
            var missing: [REAPI.Digest: URL] = [:]
            for digest in digests where !hasBlob(digest) {
                missing[digest] = staging.appendingPathComponent(digest.hash)
            }
            guard !missing.isEmpty else { return true }
            guard let remote, let download = try? await remote.downloadBlobs(missing) else { return false }
            for (digest, file) in missing {
                guard download.available.contains(digest), (try? REAPI.digest(file: file)) == digest,
                      (try? publish(file, digest: digest)) != nil else { return false }
            }
            return true
        }

        private func isSafe(_ path: String) -> Bool {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            return !path.hasPrefix("/") && !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        }

        func store(log: URL, started: Date, stdout: Data, stderr: Data, remote: (any REAPICacheStoring)?) async {
            let temporary = [NSTemporaryDirectory(), "/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]
                .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            guard let reads = CargoReadSet.parse(
                log: log, relocation: relocation, excludedRoots: [session.path, root.path],
                targetDirectory: environment["TUIST_CARGO_TARGET_DIR"].map { URL(fileURLWithPath: $0).standardizedFileURL.path },
                allowedWrites: [outDirectory.path] + temporary,
                keyedEnvironment: Self.isKeyed
            ) else {
                debug("build-script run is not cacheable: its reads were not fully recorded")
                return
            }
            guard reads.unchanged(since: started, relocation: relocation) else {
                debug("build-script run is not cacheable: an input changed while it ran")
                return
            }
            let key: REAPI.Digest
            do { key = try self.key(reads) } catch {
                debug("build-script run is not cacheable: its inputs cannot be read (\(error))")
                return
            }
            guard let (command, action, actionDigest) = actionDigest(key) else { return }
            let staging = root.appendingPathComponent("staging/" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                var blobs: [REAPI.Digest: URL] = [:]
                var budget = maximumBytes
                func keep(_ data: Data, path: String, executable: Bool = false) throws -> Outputs.File? {
                    // Text naming a root is stored relocated; binary content naming one cannot be.
                    let containsRoot = !relocation.boundRoots(in: data).isEmpty
                    guard let stored = containsRoot ? relocation.relative(data) : data else { return nil }
                    budget -= Int64(stored.count)
                    guard budget >= 0 else { return nil }
                    let digest = REAPI.digest(stored)
                    let file = staging.appendingPathComponent(UUID().uuidString)
                    try stored.write(to: file)
                    blobs[digest] = try publish(file, digest: digest)
                    return Outputs.File(
                        path: path, hash: digest.hash, size: digest.sizeBytes, executable: executable, relocated: containsRoot
                    )
                }
                guard let stdoutFile = try keep(stdout, path: "stdout"), let stderrFile = try keep(stderr, path: "stderr"),
                      let entries = FileManager.default.enumerator(atPath: outDirectory.path)
                else { debug("build-script output names this checkout"); return }
                var files: [Outputs.File] = []
                var directories: [String] = []
                for case let path as String in entries {
                    let url = outDirectory.appendingPathComponent(path)
                    let properties = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
                    guard properties.isSymbolicLink != true,
                          files.count < 10000 else { debug("unsupported OUT_DIR entry"); return }
                    if properties.isDirectory == true { directories.append(path); continue }
                    guard properties.isRegularFile == true,
                          let file = try keep(
                              Data(contentsOf: url),
                              path: path,
                              executable: FileManager.default.isExecutableFile(atPath: url.path)
                          )
                    else { debug("build-script output \(path) is not cacheable"); return }
                    files.append(file)
                }
                // The outputs must still be what the script wrote: nothing else may change them meanwhile.
                guard reads.unchanged(since: started, relocation: relocation), (try? self.key(reads)) == key else { return }
                let manifest = try JSONEncoder().encode(Outputs(
                    stdout: stdoutFile, stderr: stderrFile, directories: directories.sorted(), files: files
                ))
                let manifestFile = staging.appendingPathComponent("outputs.json")
                try manifest.write(to: manifestFile)
                let manifestDigest = REAPI.digest(manifest)
                blobs[manifestDigest] = try publish(manifestFile, digest: manifestDigest)
                var result = REAPI.ActionResult()
                result.outputFiles = [.with { $0.path = "outputs.json"; $0.digest = manifestDigest }]
                try write(result.serializedData(), to: root.appendingPathComponent("script-actions/" + actionDigest.hash))
                await index.put(reads, remote: remote, environment: environment)
                guard let remote else { return }
                if let marker = CargoCacheSetup.readOnlyMarker(environment: environment),
                   FileManager.default.fileExists(atPath: marker.path) { return }
                for (offset, data) in [command, Data()].enumerated() {
                    let file = staging.appendingPathComponent("request-\(offset)")
                    try data.write(to: file)
                    blobs[REAPI.digest(data)] = file
                }
                let actionFile = staging.appendingPathComponent("action")
                try action.write(to: actionFile)
                blobs[actionDigest] = actionFile
                let upload = try await remote.uploadAvailableBlobs(blobs)
                guard upload.available.isSuperset(of: Set(blobs.keys)) else { return }
                try await remote.storeActionResult(result, for: actionDigest)
            } catch { debug("build-script run was not stored: \(error)") }
        }

        private func publish(_ file: URL, digest: REAPI.Digest) throws -> URL {
            let destination = blobPath(digest)
            if hasBlob(digest) { return destination }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.copyItem(at: file, to: temporary)
            guard try REAPI.digest(file: temporary) == digest else { throw REAPICacheError.corruptBlob }
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        }

        private func write(_ data: Data, to file: URL) throws {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        }

        func debug(_ message: String) {
            if environment["TUIST_DEBUG"] == "1" { FileHandle.standardError.write(Data("Tuist Cargo cache: \(message)\n".utf8)) }
        }
    }
}
