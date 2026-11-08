import Foundation
import Path
import TuistProcess
import TuistREAPI
import TuistServer

struct CargoCompilerObserver {
    let runner: CommandRunning
    /// The session's REAPI connection, when the outer command serves this hook; otherwise the hook connects itself.
    var sessionRemote: Task<(any REAPICacheStoring)?, Never>?

    init(runner: CommandRunning, sessionRemote: Task<(any REAPICacheStoring)?, Never>? = nil) {
        self.runner = runner
        self.sessionRemote = sessionRemote
    }

    /// The remote cache for one hook, `nil` once the session's circuit is open.
    static func connect(
        _ environment: [String: String], session: Task<(any REAPICacheStoring)?, Never>?
    ) async -> (any REAPICacheStoring)? {
        guard let session else { return try? await remote(environment) }
        if let marker = remoteFailureMarker(environment), FileManager.default.fileExists(atPath: marker.path) { return nil }
        return await session.value
    }

    /// What a hook does next: replay a hit's compiler messages, or run the compiler and publish what it produced.
    enum Decision {
        case replayed(stdout: Data, stderr: Data)
        case compile(CargoCompilerRun)
    }

    func run(_ arguments: [String], environment: [String: String], directory: AbsolutePath, native: Bool = false) async throws {
        switch try await decide(arguments, environment: environment, directory: directory, native: native) {
        case let .replayed(stdout, stderr):
            FileHandle.standardOutput.write(stdout)
            FileHandle.standardError.write(stderr)
        case let .compile(compilation):
            do {
                for try await event in runner.run(
                    arguments: compilation.command, environment: compilation.environment, workingDirectory: directory
                ) {
                    switch event {
                    case let .standardOutput(bytes):
                        FileHandle.standardOutput.write(Data(bytes))
                        compilation.standardOutput(Data(bytes))
                    case let .standardError(bytes):
                        FileHandle.standardError.write(compilation.standardError(Data(bytes)))
                    }
                }
            } catch {
                await compilation.finish(succeeded: false)
                throw error
            }
            await compilation.finish(succeeded: true)
        }
    }

    func decide(
        _ arguments: [String], environment: [String: String], directory: AbsolutePath, native: Bool = false
    ) async throws -> Decision {
        guard let compiler = arguments.first else { throw CargoReportError(message: "Missing compiler executable.") }
        // A build script being recorded runs `cc` through the protected `/bin/sh` shim, which drops the recorder: the
        // compiler starts recorded again, as the script's child, so everything it reads or finds missing joins the
        // script's reads and the run is cached as a whole, not compilation by compilation. `/usr/bin/cc` is a
        // protected `xcrun` shim as well, so this starts the clang it selects, with the SDK it would set.
        if native, let log = environment["TUIST_CARGO_READ_LOG"],
           environment[CargoReadRecorder.scriptLogVariable] == log,
           let recorder = environment["TUIST_CARGO_RECORDER"],
           compiler == "/usr/bin/cc", let clang = environment["TUIST_CARGO_CACHE_CLANG"],
           let sdk = try? await CargoToolchainIdentity.linker(
               environment: environment, directory: directory, process: CargoProcess(runner: runner)
           ).first?.trimmingCharacters(in: .whitespacesAndNewlines), sdk.hasPrefix("/")
        {
            var recorded = environment
            recorded["DYLD_INSERT_LIBRARIES"] = recorder
            if recorded["SDKROOT"] == nil { recorded["SDKROOT"] = sdk }
            // Like rustc's `--remap-path-prefix`: debug information naming the checkout would bind every crate that
            // embeds the output (mise links a helper this way) to that path. C does not read the Rust sysroot, and
            // `/` is not a root. The script's own mappings come later, so they still win.
            let maps = CargoRelocation(environment: environment, sysroot: URL(fileURLWithPath: "/")).debugPrefixMapArguments
            return .compile(CargoCompilerRun(
                command: [clang] + maps + arguments.dropFirst(), environment: recorded, arguments: arguments,
                hookEnvironment: environment, directory: directory, native: true, runner: runner, invocation: nil,
                recorded: nil, cache: nil, measurement: nil, remote: nil, log: nil, strict: false
            ))
        }
        var invocation: (any CargoCacheAction)?
        var recorded: CargoRecordedInvocation?
        var remote: (any REAPICacheStoring)?
        var remoteResolved = false
        if native {
            invocation = try? await CargoClangInvocation.prepare(
                arguments, environment: environment, directory: directory, process: CargoProcess(runner: runner)
            )
        } else {
            invocation = await Self.unlessFailed(environment) {
                try await CargoCacheInvocation.prepare(
                    arguments, environment: environment, directory: directory, process: CargoProcess(runner: runner)
                )
            }
        }
        if let rust = invocation as? CargoCacheInvocation, rust.isDeferred {
            // Another machine may have compiled this crate: its remembered sources key a lookup without rustc.
            remote = await Self.connect(environment, session: sessionRemote)
            remoteResolved = true
            if let listed = await rust.sourceIndex?.get(remote: remote), let keyed = try? rust.keyed(sources: listed) {
                invocation = keyed
            }
        }
        // A deferred compilation learns only after rustc whether strict admission accepts its sources, so it is
        // recorded as well: when admission refuses them (assembly, `#[link]`), its reads key it instead.
        if !native, invocation == nil || (invocation as? CargoCacheInvocation)?.isDeferred == true {
            recorded = await Self.unlessFailed(environment) {
                try await CargoRecordedInvocation.prepare(
                    arguments, environment: environment, directory: directory, process: CargoProcess(runner: runner)
                )
            }
        }
        if let candidate = recorded, let index = candidate.index {
            var reads = await index.get(remote: nil)
            if reads == nil {
                if !remoteResolved { remote = await Self.connect(environment, session: sessionRemote) }
                remoteResolved = true
                reads = await index.get(remote: remote)
            }
            if let found = reads.flatMap(candidate.with) {
                invocation = found
            } else if !(invocation is CargoCacheInvocation) {
                invocation = nil
            }
        }
        let deferred = (invocation as? CargoCacheInvocation)?.isDeferred == true
        let measurement = (invocation ?? recorded).map(CargoCacheMeasurement.init)
        var cache: CargoCompilationCache?
        let replayed = CargoReplay()
        if let invocation, let measurement, let root = environment["TUIST_CARGO_CACHE_DIR"] {
            cache = try? CargoCompilationCache(
                invocation: invocation, root: URL(fileURLWithPath: root), remote: nil, measurement: measurement
            )
            cache?.replay = { replayed.stdout = $0; replayed.stderr = $1 }
        } else { cache = nil }
        if !deferred, let cache, try await cache.restoreLocally() {
            measurement?.outcome(hit: true)
            measurement?.write()
            await installBuildScript(arguments, environment: environment, directory: directory, native: native)
            return .replayed(stdout: replayed.stdout, stderr: replayed.stderr)
        }
        if cache != nil || recorded != nil, !remoteResolved {
            remote = await Self.connect(environment, session: sessionRemote)
        }
        cache?.remote = remote
        if !deferred, let cache, try await cache.restoreRemotely() {
            measurement?.outcome(hit: true)
            measurement?.write()
            await installBuildScript(arguments, environment: environment, directory: directory, native: native)
            return .replayed(stdout: replayed.stdout, stderr: replayed.stderr)
        }
        try Task.checkCancellation()
        if measurement?.hasRemoteFailure == true {
            cache?.remote = nil
            remote = nil
            if let marker = Self.remoteFailureMarker(environment) { try? Data().write(to: marker, options: .atomic) }
        }
        measurement?.outcome(hit: false)
        // A strict invocation runs as it was keyed; any other cacheable compilation runs recorded.
        let strict = invocation is CargoCacheInvocation || invocation is CargoClangInvocation
        let log = recorded.flatMap { _ in environment["TUIST_CARGO_SESSION"] }
            .map { URL(fileURLWithPath: $0).appendingPathComponent("reads-\(UUID().uuidString).log") }
        let compileEnvironment = log.flatMap { recorded?.recordingEnvironment(log: $0) } ?? environment
        var remap = strict ? invocation?.remapArguments ?? [] : recorded?.remapArguments ?? []
        if remap.isEmpty, !native, environment["TUIST_CARGO_WORKSPACE_ROOT"] != nil, arguments.contains("--crate-name"),
           !arguments.contains(where: { $0.hasPrefix("--print") || $0.hasPrefix("--remap-path-prefix") }),
           let identity = try? await CargoToolchainIdentity.resolve(
               compiler, environment: environment, directory: directory, process: CargoProcess(runner: runner)
           )
        {
            remap = CargoRelocation(environment: environment, sysroot: identity.sysroot).remapArguments
        }
        let wrapper = environment["TUIST_CARGO_INNER_WRAPPER"].flatMap { $0.isEmpty ? nil : $0 }
        // A recorded compiler starts directly: `/usr/bin/env` is protected, and macOS drops `DYLD_*` when it starts.
        // It is the toolchain's own rustc, never the rustup proxy, which reads the whole environment and
        // rustup's settings: recording those would key every compilation on unrelated variables.
        let command = (log != nil ?
            [recorded.map { $0.toolchain.appendingPathComponent("bin/rustc").path } ?? Self.executablePath(
                compiler,
                environment: environment,
                directory: directory
            )]
            : ["/usr/bin/env", wrapper ?? compiler]) + (wrapper == nil ? Array(arguments.dropFirst()) : arguments)
            + remap
        return .compile(CargoCompilerRun(
            command: command, environment: compileEnvironment, arguments: arguments, hookEnvironment: environment,
            directory: directory, native: native, runner: runner, invocation: invocation, recorded: recorded,
            cache: cache, measurement: measurement, remote: remote, log: log, strict: strict
        ))
    }

    /// Runs a preparation whose refusal means "not cacheable". Any other failure (a probe that could not run) is
    /// reported under `TUIST_DEBUG`, because it silently turns caching off for the crate.
    private static func unlessFailed<T>(_ environment: [String: String], _ body: () async throws -> T?) async -> T? {
        do { return try await body() } catch {
            if !(error is CargoCacheInvocation.CacheError), environment["TUIST_DEBUG"] == "1" {
                FileHandle.standardError.write(Data("Tuist Cargo cache: preparation failed: \(error)\n".utf8))
            }
            return nil
        }
    }

    /// A restored build script is shimmed as a compiled one is, so its run is cached as well.
    private func installBuildScript(_ arguments: [String], environment: [String: String], directory: AbsolutePath, native: Bool)
        async
    {
        guard !native else { return }
        try? await CargoBuildScript.install(
            arguments,
            environment: environment,
            directory: directory,
            process: CargoProcess(runner: runner)
        )
    }

    private static func executablePath(_ executable: String, environment: [String: String], directory: AbsolutePath) -> String {
        let base = URL(fileURLWithPath: directory.pathString, isDirectory: true)
        if executable.contains("/") { return URL(fileURLWithPath: executable, relativeTo: base).standardizedFileURL.path }
        return (environment["PATH"] ?? "").components(separatedBy: ":")
            .map { URL(fileURLWithPath: $0.isEmpty ? "." : $0, relativeTo: base).appendingPathComponent(executable).path }
            .first(where: FileManager.default.isExecutableFile(atPath:)) ?? executable
    }

    private static func remoteFailureMarker(_ environment: [String: String]) -> URL? {
        environment["TUIST_CARGO_SESSION"].map { URL(fileURLWithPath: $0).appendingPathComponent("cache-remote-unavailable") }
    }

    static func remote(_ environment: [String: String], connectionCount: Int = 1) async throws -> (any REAPICacheStoring)? {
        if let marker = remoteFailureMarker(environment), FileManager.default.fileExists(atPath: marker.path) { return nil }
        if let broker = environment["TUIST_CARGO_CACHE_BROKER"] {
            return CargoRemoteCache(directory: URL(fileURLWithPath: broker))
        }
        guard let address = environment["TUIST_CARGO_CACHE_REMOTE_URL"], let url = URL(string: address), let host = url.host,
              let namespace = environment["TUIST_CARGO_CACHE_NAMESPACE"],
              let scope = CargoCacheScope(fullHandle: namespace),
              let file = environment["TUIST_CARGO_CACHE_TOKEN_FILE"] else { return nil }
        let client = try await REAPICacheClient(
            endpoint: GRPCEndpoint(host: host, explicitPort: url.port, isTLS: url.scheme == "https" || url.scheme == "grpcs"),
            accountHandle: scope.accountHandle, instanceName: scope.instanceName,
            metadataTimeout: CargoRemoteCache.metadataTimeout, connectionCount: connectionCount, environment: environment,
            chunkCacheDirectory: environment["TUIST_CARGO_CACHE_DIR"].map {
                URL(fileURLWithPath: $0).appendingPathComponent("blobs")
            },
            token: { try String(contentsOfFile: file, encoding: .utf8) }
        )
        try await client.validateCapabilities()
        return client
    }

    static func diagnostics(
        from pending: inout Data, remaining: Int, invocation: (any CargoCacheAction)?
    ) -> [CargoDiagnostic] {
        var result: [CargoDiagnostic] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline)
            pending.removeSubrange(...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if json["$message_type"] as? String == "artifact", json["emit"] as? String == "metadata" {
                // Cargo pipelines dependents as soon as this notification is forwarded. Certify
                // the atomically installed metadata first; this is admission, not cache publication.
                try? invocation?.certifyOutputs(metadataOnly: true)
            }
            guard result.count < remaining,
                  let level = json["level"] as? String, ["error", "warning"].contains(level),
                  let message = json["message"] as? String else { continue }
            let span = (json["spans"] as? [[String: Any]])?.first { $0["is_primary"] as? Bool == true }
            result.append(.init(
                severity: level,
                message: String(message.prefix(10000)),
                file: span?["file_name"] as? String,
                line: span?["line_start"] as? Int
            ))
        }
        return result
    }

    func record(
        _ arguments: [String],
        environment: [String: String],
        started: Date,
        failed: Bool,
        diagnostics: [CargoDiagnostic]
    ) {
        guard let session = environment["TUIST_CARGO_SESSION"],
              let origin = environment["TUIST_CARGO_STARTED"].flatMap(Double.init),
              let source = arguments.dropFirst().first(where: { $0.hasSuffix(".rs") }),
              !arguments.contains("--print") else { return }
        func option(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        let dependencies = arguments.enumerated().compactMap { index, value -> String? in
            guard value == "--extern", index + 1 < arguments.count else { return nil }
            return arguments[index + 1].components(separatedBy: "=").first
        }
        let compilation = CargoCompilation(
            name: option("--crate-name") ?? "unknown", source: source,
            kind: arguments.contains("--test") ? "test" : option("--crate-type") ?? "lib",
            dependencies: Array(dependencies.prefix(5000)),
            startOffsetMs: CargoCommandService.milliseconds(started.timeIntervalSince1970 - origin),
            durationMs: CargoCommandService.milliseconds(Date().timeIntervalSince(started)),
            status: failed ? "failure" : "success", diagnostics: diagnostics
        )
        if let data = try? JSONEncoder().encode(compilation) {
            try? data.write(
                to: URL(fileURLWithPath: session).appendingPathComponent(UUID().uuidString + ".json"),
                options: .atomic
            )
        }
    }
}
