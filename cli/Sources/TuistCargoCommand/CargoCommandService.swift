import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistProcess
import TuistREAPI
import TuistServer

struct CargoExecutionContext {
    let executable: String
    let directory: AbsolutePath
    let arguments: [String]
    let environment: [String: String]
    let reporting: CargoReporting
    var shardOptions: [String: Int] = [:]
}

public struct CargoCommandService { // swiftlint:disable:this type_body_length
    private let runner: CommandRunning
    public init(runner: CommandRunning = CommandRunner()) { self.runner = runner }

    public func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        directory: AbsolutePath? = nil
    ) async throws {
        var environment = environment
        let directory = try directory ?? AbsolutePath(validating: FileManager.default.currentDirectoryPath)
        let parsed = ["test", "t"].contains(CargoInvocation(arguments).command ?? "")
            ? try CargoTestSelection.planning(arguments) : (arguments: arguments, options: [:])
        let invocation = CargoInvocation(parsed.arguments)
        if let toolchain = invocation.toolchain { environment["RUSTUP_TOOLCHAIN"] = toolchain }
        if arguments.first == "__script", arguments.count >= 2 {
            try await CargoBuildScript.run(
                real: arguments[1], arguments: Array(arguments.dropFirst(2)), environment: environment,
                directory: directory, runner: runner
            )
            return
        }
        if arguments.first == "__compiler" || arguments.first == "__native" {
            try await CargoCompilerObserver(runner: runner).run(
                Array(arguments.dropFirst()),
                environment: environment,
                directory: directory,
                native: arguments.first == "__native"
            )
            return
        }
        let process = CargoProcess(runner: runner)
        let resolved = try await process.executable(invocation: invocation, environment: environment, directory: directory)
        let executable = resolved.path
        // A rustup proxy pins its selection before Cargo changes directories to compile workspace members.
        if let toolchain = resolved.toolchain { environment["RUSTUP_TOOLCHAIN"] = toolchain }
        try Task.checkCancellation()
        let isSharding = invocation.command == "test-build" || environment["TUIST_SHARD_INDEX"] != nil || !parsed.options.isEmpty
        try validateShardingDirectory(invocation: invocation, isSharding: isSharding)
        if environment["TUIST_CARGO_ACTIVE"] == nil, invocation.observesBuild {
            do {
                if var context = try await context(
                    executable: executable,
                    invocation: invocation,
                    directory: directory,
                    environment: environment,
                    isSharding: isSharding
                ) {
                    context.shardOptions = parsed.options
                    try await decorate(context)
                    return
                }
            } catch let error as CommandError {
                throw error
            } catch {
                if isSharding || Task
                    .isCancelled || error is CancellationError || error is CargoTestSelectionError { throw error }
                if environment["TUIST_DEBUG"] ==
                    "1"
                {
                    FileHandle.standardError
                        .write(Data("Tuist Cargo observation unavailable: \(error.localizedDescription)\n".utf8))
                }
            }
        }
        try await process.execute(
            executable,
            arguments: invocation.cargoArguments,
            environment: environment,
            directory: directory
        )
    }

    private func validateShardingDirectory(invocation: CargoInvocation, isSharding: Bool) throws {
        if invocation.changesDirectory, isSharding,
           !invocation.arguments.contains("--help"), !invocation.arguments.contains("-h")
        {
            throw CargoReportError(
                message: "Rust sharding does not support Cargo's -C option. Change into the workspace before invoking Tuist."
            )
        }
    }

    private func context(
        executable: String,
        invocation: CargoInvocation,
        directory: AbsolutePath,
        environment: [String: String],
        isSharding: Bool
    ) async throws -> CargoExecutionContext? {
        let config = try? await ConfigLoader().loadCargoConfig(path: directory)
        guard let handle = environment["TUIST_PROJECT"] ?? config?.fullHandle else {
            if isSharding {
                throw CargoReportError(
                    message: "Configure a project in tuist.toml or TUIST_PROJECT before planning or executing shards."
                )
            }
            return nil
        }
        let server = environment["TUIST_URL"] ?? config?.url.absoluteString ?? "https://tuist.dev"
        guard let serverURL = URL(string: server), ["https", "http"].contains(serverURL.scheme ?? ""),
              serverURL.host != nil
        else {
            throw CargoReportError(message: "Invalid Tuist server URL.")
        }
        let reporting = CargoReporting(
            process: CargoProcess(runner: runner),
            directory: directory,
            environment: environment,
            handle: handle,
            serverURL: serverURL
        )
        return CargoExecutionContext(
            executable: executable,
            directory: directory,
            arguments: invocation.cargoArguments,
            environment: environment,
            reporting: reporting
        )
    }

    private func decorate(_ context: CargoExecutionContext) async throws {
        // Only reports read the metadata, so its probes run alongside the build.
        let metadata = Task { await context.reporting.metadata() }
        let innerWrapper = try CargoConfiguration.compilerWrapper(
            directory: URL(fileURLWithPath: context.directory.pathString),
            arguments: context.arguments,
            environment: context.environment
        )
        try await FileSystem().runInTemporaryDirectory(prefix: "tuist-cargo") { temporary in
            let root = URL(fileURLWithPath: temporary.pathString)
            var environment = context.environment
            environment["TUIST_CARGO_ACTIVE"] = "1"
            environment["TUIST_CARGO_SESSION"] = root.path
            environment["TUIST_CARGO_INNER_WRAPPER"] = innerWrapper
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            let configured = CargoExecutionContext(
                executable: context.executable, directory: context.directory, arguments: context.arguments,
                environment: environment, reporting: context.reporting
            )
            let cache = await CargoCacheSetup().prepare(configured, root: root)
            defer { cache?.refresh?.cancel() }
            if let cache {
                environment = (try? await CargoClangInvocation.configure(
                    environment: cache.environment, directory: context.directory, process: CargoProcess(runner: runner)
                )) ?? cache.environment
            }
            // The connection is negotiated while Cargo's metadata and the toolchain are probed, so fetching starts
            // as soon as the manifest's key is known.
            let remoteEnvironment = environment
            let connecting: Task<(any REAPICacheStoring)?, Never>? = cache != nil
                && remoteEnvironment["TUIST_CARGO_CACHE_REMOTE_URL"] != nil
                ? Task { try? await CargoCompilerObserver.remote(remoteEnvironment, connectionCount: 4) } : nil
            // Hooks served by this process start a small native client instead of the whole Swift binary.
            var hookServer: CargoHookServer?
            defer { hookServer?.stop() }
            if innerWrapper == nil, let directory = environment["TUIST_CARGO_CACHE_DIR"],
               // At its stable path in the cache: Cargo keys `.rustc_info.json` on the wrapper's path and modification
               // time, so a per-session copy would make Cargo probe rustc again on every build.
               let client = CargoHookServer.client(cacheDirectory: URL(fileURLWithPath: directory)),
               let fallback = try? CargoProcess.ownExecutable(),
               let server = CargoHookServer(runner: runner, remote: connecting)
            {
                server.start()
                hookServer = server
                // Before units restore, so the digests restoration records stay in memory too.
                CargoInputHasher.serve(session: root, seed: nil)
                environment[CargoHookServer.socketVariable] = server.socketPath
                environment[CargoHookServer.fallbackVariable] = fallback
                environment[CargoHookServer.nativeVariable] = client.path
                environment["RUSTC_WRAPPER"] = client.path
                environment["CARGO_BUILD_RUSTC_WRAPPER"] = nil
            } else if innerWrapper == nil {
                let wrapper = root.appendingPathComponent("rustc-observer")
                try "#!/bin/sh\nexec \(CargoInvocation.shellQuote(try CargoProcess.ownExecutable())) cargo __compiler \"$@\"\n"
                    .write(
                        to: wrapper,
                        atomically: true,
                        encoding: .utf8
                    )
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
                environment["RUSTC_WRAPPER"] = wrapper.path
                environment["CARGO_BUILD_RUSTC_WRAPPER"] = nil
            }
            // Hooks in other processes (the shell wrapper) share this process's connection through a file broker;
            // served hooks use it directly.
            let broker = root.appendingPathComponent("cache-broker")
            var brokerReady = false
            if hookServer == nil, environment["TUIST_CARGO_CACHE_REMOTE_URL"] != nil {
                do {
                    try FileManager.default.createDirectory(
                        at: broker, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
                    )
                    environment["TUIST_CARGO_CACHE_BROKER"] = broker.path
                    brokerReady = true
                } catch { environment["TUIST_CARGO_CACHE_REMOTE_URL"] = nil }
            }
            let started = Date()
            environment["TUIST_CARGO_STARTED"] = String(started.timeIntervalSince1970)
            // Like blaze's answers, the session resolves the toolchain and linker once, before Cargo starts its first
            // wave of compilations: hooks that all missed the memo at once would each spawn rustc and xcrun probes.
            let toolchain = cache == nil ? nil : Task { [environment, runner] in
                try? await CargoToolchainIdentity.resolve(
                    environment["RUSTC"] ?? "rustc", environment: environment, directory: context.directory,
                    process: CargoProcess(runner: runner)
                )
            }
            let served = hookServer != nil
            defer { if served { CargoInputHasher.stopServing(session: root) } }
            let identities = cache == nil ? nil : Task { [environment, runner] in
                let process = CargoProcess(runner: runner)
                let directory = context.directory
                if let identity = await toolchain?.value, let session = environment["TUIST_CARGO_SESSION"] {
                    identity.prewarm(
                        session: URL(fileURLWithPath: session),
                        cache: environment["TUIST_CARGO_CACHE_DIR"].map { URL(fileURLWithPath: $0) },
                        served: served
                    )
                }
                #if os(macOS)
                    _ = try? await CargoToolchainIdentity.linker(environment: environment, directory: directory, process: process)
                #endif
            }
            var unitCache = cache == nil ? nil : await CargoUnitCache.prepare(
                executable: context.executable, arguments: context.arguments, environment: environment,
                directory: context.directory, toolchain: await toolchain?.value, process: CargoProcess(runner: runner)
            )
            if unitCache != nil { unitCache?.remote = await connecting?.value } else if hookServer == nil { connecting?.cancel() }
            if let unitCache {
                if unitCache.remote != nil { environment[CargoCacheJournal.writeBehindVariable] = "1" }
                environment["TUIST_CARGO_TARGET_DIR"] = unitCache.targetDirectory.path
                environment["TUIST_CARGO_WORKSPACE_ROOT"] = unitCache.workspaceRoot.path
                // Recorded compilations and build-script runs need relocatable roots, so they share its scope.
                if let library = CargoReadRecorder.prepare(cacheDirectory: unitCache.root) {
                    environment["TUIST_CARGO_RECORDER"] = library.path
                    // Served sessions start build-script runs with the hook client as well.
                    environment["TUIST_CARGO_SCRIPT"] = hookServer == nil ? try? CargoProcess.ownExecutable()
                        : environment["RUSTC_WRAPPER"]
                }
            }
            let manifest = await unitCache?.manifest()
            let units = unitCache
            // Per-crate entries download while units are restored and Cargo works through dependencies.
            let prefetch = Task { await units?.prefetch(manifest) }
            let restored = await unitCache?.restore(manifest) ?? CargoUnitCache.Restored()
            await identities?.value
            let child = CargoExecutionContext(
                executable: context.executable,
                directory: context.directory,
                arguments: context.arguments,
                environment: environment,
                reporting: context.reporting,
                shardOptions: context.shardOptions
            )
            try await withThrowingTaskGroup(of: Void.self) { group in
                if brokerReady {
                    group.addTask {
                        try? await CargoRemoteCache.serve(directory: broker, prepare: {
                            try await CargoCompilerObserver.remote(remoteEnvironment, connectionCount: 4)
                        })
                    }
                }
                defer { group.cancelAll() }
                try Task.checkCancellation()
                defer { prefetch.cancel() }
                do {
                    try await executeSession(child, root: root, started: started, drain: { [hookServer] in
                        await hookServer?.drain()
                    }, metadata: {
                        var result = await metadata.value
                        if let version = await toolchain?.value?.version.split(separator: "\n").first {
                            result["rust_version"] = String(version)
                        } else {
                            result["rust_version"] = await context.reporting.rustVersion()
                        }
                        return result
                    })
                } catch {
                    await Self.publishDeferred(root: root, units: units)
                    throw error
                }
                prefetch.cancel()
                await prefetch.value
                await Self.publishDeferred(root: root, units: units)
                await units?.store(reusing: restored, used: CargoCacheJournal.used(session: root))
            }
        }
    }

    /// Uploads what compiler hooks left for after the build (write-behind), even when the build failed.
    private static func publishDeferred(root: URL, units: CargoUnitCache?) async {
        guard let remote = units?.remote else { return }
        await CargoCacheJournal.flush(session: root, remote: remote) { message in
            if ProcessInfo.processInfo.environment["TUIST_DEBUG"] == "1" {
                FileHandle.standardError.write(Data("Tuist Cargo cache: \(message)\n".utf8))
            }
        }
    }

    private func executeSession(
        _ context: CargoExecutionContext,
        root: URL,
        started: Date,
        drain: () async -> Void,
        metadata: () async -> [String: Any]
    ) async throws {
        let invocation = CargoInvocation(context.arguments)
        var executionError: Error?
        var nextest: CargoNextestRun?
        var cargoTests: CargoTestResult?
        var selectsCargoTests = false
        do {
            if !context.shardOptions.isEmpty {
                guard context.environment["TUIST_SHARD_INDEX"] == nil else {
                    throw CargoTestSelectionError(message: "Cannot plan and execute a Cargo shard in the same command.")
                }
                try await CargoTestSelection(runner: runner).plan(context, options: context.shardOptions)
            } else if invocation.command == "test-build" {
                try await CargoShardService(runner: runner).plan(
                    arguments: context.arguments,
                    executable: context.executable,
                    directory: context.directory,
                    environment: context.environment,
                    fullHandle: context.reporting.handle,
                    serverURL: context.reporting.serverURL
                )
            } else {
                if invocation.isNextestRun {
                    nextest = try await CargoNextestService(runner: runner).prepare(context, root: root)
                } else if context.environment["TUIST_SHARD_INDEX"] != nil, !invocation.executesTests {
                    throw CargoTestSelectionError(message: "Execute plain Cargo shards with 'tuist cargo test'.")
                }
                if invocation.executesTests {
                    let quarantine = await CargoTestQuarantine.fetch(context)
                    if context.environment["TUIST_SHARD_INDEX"] != nil || !quarantine.muted.isEmpty || !quarantine.skipped
                        .isEmpty
                    {
                        selectsCargoTests = true
                        try await CargoTestSelection(runner: runner).execute(context, quarantine: quarantine) { cargoTests = $0 }
                    } else if CargoTestService.observes(invocation, environment: context.environment) {
                        try await CargoTestService(runner: runner).execute(context) { cargoTests = $0 }
                    } else {
                        try await context.reporting.process.execute(
                            context.executable, arguments: context.arguments,
                            environment: context.environment, directory: context.directory
                        )
                    }
                } else {
                    try await context.reporting.process.execute(
                        context.executable,
                        arguments: nextest?.arguments ?? context.arguments,
                        environment: context.environment,
                        directory: context.directory
                    )
                }
            }
        } catch { executionError = error }
        let finished = Date()
        // Hooks publish after reporting their compiler's exit; their measurements and stored entries are complete
        // once they are done.
        await drain()
        let metadata = await metadata()
        if context.shardOptions.isEmpty, invocation.reportsBuild, !invocation.executesTests || cargoTests != nil {
            await context.reporting.build(
                root: root,
                started: started,
                finished: finished,
                command: invocation.command ?? "",
                metadata: metadata,
                failed: executionError != nil,
                testResult: cargoTests
            )
        }
        if let nextest { await context.reporting.tests(run: nextest, metadata: metadata, failed: executionError != nil) }
        if let report = cargoTests?.report {
            await context.reporting.tests(
                report: report, metadata: metadata, failed: executionError != nil,
                shardID: cargoTests?.shardID, shardIndex: cargoTests?.shardIndex
            )
        }
        if let executionError {
            if selectsCargoTests, !(executionError is CommandError), !(executionError is CancellationError) {
                throw CargoTestSelectionError(message: executionError.localizedDescription)
            }
            throw executionError
        }
    }

    static func milliseconds(_ seconds: Double) -> Int { Int(min(max((seconds * 1000).rounded(), 0), Double(UInt32.max))) }
    static func listArguments(_ arguments: [String]) -> [String] { CargoNextestService.listArguments(arguments) }
}
