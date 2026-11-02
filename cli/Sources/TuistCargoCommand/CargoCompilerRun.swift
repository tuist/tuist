import Foundation
import Path
import TuistProcess
import TuistREAPI

/// A hit's compiler messages, collected for whoever replays them.
final class CargoReplay {
    var stdout = Data()
    var stderr = Data()
}

/// A process a hook runs for the cache: whoever runs `command` feeds the run its output, forwards the standard error
/// `standardError` returns, then calls `finish`.
protocol CargoHookRun: AnyObject {
    var command: [String] { get }
    var environment: [String: String] { get }
    func standardOutput(_ bytes: Data)
    func standardError(_ bytes: Data) -> Data
    func finish(succeeded: Bool) async
}

/// A compilation the cache missed, from the compiler's start to publication. Whoever runs `command` (this process, or
/// the hook client of a served session, which keeps Cargo's jobserver and stdio) feeds it the compiler's output and
/// forwards the standard error `standardError` returns, then calls `finish`.
final class CargoCompilerRun: CargoHookRun {
    let command: [String]
    let environment: [String: String]
    private let arguments: [String]
    private let hookEnvironment: [String: String]
    private let directory: AbsolutePath
    private let native: Bool
    private let runner: CommandRunning
    private let invocation: (any CargoCacheAction)?
    private let recorded: CargoRecordedInvocation?
    private let cache: CargoCompilationCache?
    private let measurement: CargoCacheMeasurement?
    private let remote: (any REAPICacheStoring)?
    private let log: URL?
    private let strict: Bool
    private let started = Date()
    private var stdout = Data()
    private var stderr = Data()
    private var bounded = true
    private var diagnostics: [CargoDiagnostic] = []
    private var pending = Data()

    init(
        command: [String], environment: [String: String], arguments: [String], hookEnvironment: [String: String],
        directory: AbsolutePath, native: Bool, runner: CommandRunning, invocation: (any CargoCacheAction)?,
        recorded: CargoRecordedInvocation?, cache: CargoCompilationCache?, measurement: CargoCacheMeasurement?,
        remote: (any REAPICacheStoring)?, log: URL?, strict: Bool
    ) {
        self.command = command
        self.environment = environment
        self.arguments = arguments
        self.hookEnvironment = hookEnvironment
        self.directory = directory
        self.native = native
        self.runner = runner
        self.invocation = invocation
        self.recorded = recorded
        self.cache = cache
        self.measurement = measurement
        self.remote = remote
        self.log = log
        self.strict = strict
    }

    func standardOutput(_ bytes: Data) {
        if stdout.count + stderr.count + bytes.count <= 1_000_000 { stdout.append(bytes) } else { bounded = false }
    }

    /// Takes the compiler's standard error and returns it for forwarding. Cargo pipelines dependents as soon as a
    /// metadata artifact notification is forwarded, so the metadata is certified before these bytes are returned.
    func standardError(_ bytes: Data) -> Data {
        if stdout.count + stderr.count + bytes.count <= 1_000_000 { stderr.append(bytes) } else { bounded = false }
        pending.append(bytes)
        if pending.count > 1_000_000 { pending.removeAll() }
        diagnostics += CargoCompilerObserver.diagnostics(
            from: &pending, remaining: 100 - diagnostics.count, invocation: invocation
        )
        return bytes
    }

    func finish(succeeded: Bool) async {
        defer {
            measurement?.write()
            if let log { try? FileManager.default.removeItem(at: log) }
        }
        let observer = CargoCompilerObserver(runner: runner)
        observer.record(arguments, environment: hookEnvironment, started: started, failed: !succeeded, diagnostics: diagnostics)
        guard succeeded else { return }
        await store()
        // After storing: the stored outputs are the compiled build script, never the shim that replaces it.
        if !native { try? await CargoBuildScript.install(
            arguments, environment: hookEnvironment, directory: directory, process: CargoProcess(runner: runner)
        ) }
    }

    private func store() async {
        guard bounded, let root = hookEnvironment["TUIST_CARGO_CACHE_DIR"] else { return }
        var refreshed = strict ? invocation : nil
        if let rust = refreshed as? CargoCacheInvocation { refreshed = await rust.refreshed(remote: remote) }
        if var cache, let measurement, let refreshed {
            if refreshed.key != invocation?.key, let rekeyed = try? CargoCompilationCache(
                invocation: refreshed, root: URL(fileURLWithPath: root), remote: remote, measurement: measurement
            ) { cache = rekeyed }
            try? await cache.store(stdout: stdout, stderr: stderr)
        } else if let recorded, let log, let measurement, let finished = recorded.recorded(log: log, started: started),
                  let reads = finished.reads, let index = finished.index
        {
            await index.put(reads, remote: remote, environment: hookEnvironment)
            try? await CargoCompilationCache(
                invocation: finished, root: URL(fileURLWithPath: root), remote: remote, measurement: measurement
            ).store(stdout: stdout, stderr: stderr)
        }
    }
}
