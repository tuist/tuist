import Foundation
import Path
import TuistProcess
import TuistREAPI
import TuistServer

struct CargoCompilerObserver {
    let runner: CommandRunning

    func run(_ arguments: [String], environment: [String: String], directory: AbsolutePath, native: Bool = false) async throws {
        guard let compiler = arguments.first else { throw CargoReportError(message: "Missing compiler executable.") }
        var invocation: (any CargoCacheAction)?
        var recorded: CargoRecordedInvocation?
        var remote: (any REAPICacheStoring)?
        var remoteResolved = false
        if native {
            invocation = try? await CargoClangInvocation.prepare(
                arguments, environment: environment, directory: directory, process: CargoProcess(runner: runner)
            )
        } else {
            invocation = try? await CargoCacheInvocation.prepare(
                arguments, environment: environment, directory: directory, process: CargoProcess(runner: runner)
            )
            if invocation == nil {
                recorded = try? await CargoRecordedInvocation.prepare(
                    arguments, environment: environment, directory: directory, process: CargoProcess(runner: runner)
                )
            }
        }
        if let candidate = recorded, let index = candidate.index {
            var reads = await index.get(remote: nil)
            if reads == nil {
                remote = try? await Self.remote(environment)
                remoteResolved = true
                reads = await index.get(remote: remote)
            }
            invocation = reads.flatMap(candidate.with)
        }
        let measurement = (invocation ?? recorded).map(CargoCacheMeasurement.init)
        var cache: CargoCompilationCache?
        if let invocation, let measurement, let root = environment["TUIST_CARGO_CACHE_DIR"] {
            cache = try? CargoCompilationCache(
                invocation: invocation, root: URL(fileURLWithPath: root), remote: nil, measurement: measurement
            )
        } else { cache = nil }
        defer { measurement?.write() }
        if let cache, try await cache.restoreLocally() {
            measurement?.outcome(hit: true)
            return
        }
        if cache != nil || recorded != nil, !remoteResolved {
            remote = try? await Self.remote(environment)
        }
        cache?.remote = remote
        if let cache, try await cache.restoreRemotely() {
            measurement?.outcome(hit: true)
            return
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
        defer { if let log { try? FileManager.default.removeItem(at: log) } }
        let compileEnvironment = !strict ? log.flatMap { recorded?.recordingEnvironment(log: $0) } ?? environment : environment
        var remap = strict ? invocation?.remapArguments ?? [] : recorded?.remapArguments ?? []
        if remap.isEmpty, !native, environment["TUIST_CARGO_WORKSPACE_ROOT"] != nil, arguments.contains("--crate-name"),
           !arguments.contains(where: { $0.hasPrefix("--print") || $0.hasPrefix("--remap-path-prefix") }),
           let identity = try? await CargoToolchainIdentity.resolve(
               compiler, environment: environment, directory: directory, process: CargoProcess(runner: runner)
           )
        {
            remap = CargoRelocation(environment: environment, sysroot: identity.sysroot).remapArguments
        }
        let started = Date()
        var stdout = Data()
        var stderr = Data()
        var bounded = true
        let wrapper = environment["TUIST_CARGO_INNER_WRAPPER"].flatMap { $0.isEmpty ? nil : $0 }
        var executionError: Error?
        var diagnostics: [CargoDiagnostic] = []
        var pending = Data()
        do {
            for try await event in runner.run(
                // A recorded compiler starts directly: `/usr/bin/env` is protected, and macOS drops `DYLD_*` when it starts.
                arguments: (!strict && log != nil ? [Self.executablePath(
                    compiler,
                    environment: environment,
                    directory: directory
                )]
                    : ["/usr/bin/env", wrapper ?? compiler]) + (wrapper == nil ? Array(arguments.dropFirst()) : arguments)
                    + remap,
                environment: compileEnvironment, workingDirectory: directory
            ) {
                switch event {
                case let .standardOutput(bytes):
                    FileHandle.standardOutput.write(Data(bytes))
                    if stdout.count + stderr.count + bytes.count <= 1_000_000 {
                        stdout.append(contentsOf: bytes)
                    } else {
                        bounded = false
                    }
                case let .standardError(bytes):
                    if stdout.count + stderr.count + bytes.count <= 1_000_000 {
                        stderr.append(contentsOf: bytes)
                    } else {
                        bounded = false
                    }
                    pending.append(contentsOf: bytes)
                    if pending.count > 1_000_000 { pending.removeAll() }
                    diagnostics += Self.diagnostics(from: &pending, remaining: 100 - diagnostics.count, invocation: invocation)
                    FileHandle.standardError.write(Data(bytes))
                }
            }
        } catch { executionError = error }
        record(arguments, environment: environment, started: started, failed: executionError != nil, diagnostics: diagnostics)
        if let executionError { throw executionError }
        if !native { try? await CargoBuildScript.install(
            arguments,
            environment: environment,
            directory: directory,
            process: CargoProcess(runner: runner)
        ) }
        guard bounded, let root = environment["TUIST_CARGO_CACHE_DIR"] else { return }
        if strict, let cache {
            try? await cache.store(stdout: stdout, stderr: stderr)
        } else if let recorded, let log, let measurement, let finished = recorded.recorded(log: log, started: started),
                  let reads = finished.reads, let index = finished.index
        {
            await index.put(reads, remote: remote, environment: environment)
            try? await CargoCompilationCache(
                invocation: finished, root: URL(fileURLWithPath: root), remote: remote, measurement: measurement
            ).store(stdout: stdout, stderr: stderr)
        }
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

    private static func diagnostics(
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

    private func record(
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
