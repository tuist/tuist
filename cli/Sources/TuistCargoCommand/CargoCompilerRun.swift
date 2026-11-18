import Foundation
import Path
import Synchronization
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
    /// Like `finish`, but returns the part Cargo need not wait for, which the caller runs after reporting the exit.
    func settle(succeeded: Bool) async -> @Sendable () async -> Void
    /// Finishes a run whose process never reported an exit: it did not start, or its client went away. A failure, but
    /// not one a verified hit would have hidden.
    func abandon() async
    /// Like `standardError`, for a caller that can stop `command`, which lets the run hold standard error back while it
    /// looks the cache up. `nil` once that found the outputs: the caller stops the command and, once it exited, calls
    /// `restore` instead of `settle`.
    func standardErrorUnlessCached(_ bytes: Data) -> Data?
    /// The command exited on its own: what `standardErrorUnlessCached` still holds, to forward before the exit.
    func exited() -> Data
    /// Restores the outputs found while the stopped command ran: their messages to replay, and the part Cargo need not
    /// wait for. `nil` when they could not be restored after all; the run then starts over, and `command` runs again.
    func restore() async -> (messages: CargoReplay, publish: @Sendable () async -> Void)?
}

extension CargoHookRun {
    func abandon() async {
        await finish(succeeded: false)
    }

    func standardErrorUnlessCached(_ bytes: Data) -> Data? { standardError(bytes) }
    func exited() -> Data { Data() }
    func restore() async -> (messages: CargoReplay, publish: @Sendable () async -> Void)? { nil }

    func settle(succeeded: Bool) async -> @Sendable () async -> Void {
        await finish(succeeded: succeeded)
        return {}
    }
}

/// A compilation the cache missed, from the compiler's start to publication. Whoever runs `command` (this process, or
/// the hook client of a served session, which keeps Cargo's jobserver and stdio) feeds it the compiler's output and
/// forwards the standard error `standardError` returns, then calls `finish`.
final class CargoCompilerRun: CargoHookRun { // swiftlint:disable:this type_body_length
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
    /// Held until the result is stored, so another build compiling the same key restores it instead.
    private let flight: CargoFlight?
    /// A sampled hit compiled to verify it: compared with its stored entry instead of published.
    private let verification: CargoCacheVerification.Plan?
    private let started = Date()
    private var stdout = Data()
    private var stderr = Data()
    private var bounded = true
    private var abandoned = false
    private var diagnostics: [CargoDiagnostic] = []
    private var pending = Data()
    /// The artifact notifications (`emit` kinds) in the latest standard error.
    private var emitted: Set<String> = []
    /// Standard error held back while the cache may still hold this compilation (`standardErrorUnlessCached`).
    private var held: Data?
    /// Whether `held` announces rustc's metadata, which is certified when released.
    private var heldMetadata = false
    private var looksUp = true
    private var lookup: Lookup?
    private var found: Found?

    /// A compilation without a usable source list, keyed from the dep-info rustc writes right after macro expansion
    /// and looked up while rustc goes on.
    private final class Lookup {
        var task: Task<Void, Never>?
        let done = DispatchSemaphore(value: 0)
        /// `nil` while running, then the entry found, if any.
        let outcome = Mutex<Found??>(nil)
    }

    private struct Found {
        let cache: CargoCompilationCache
        let fetched: CargoCompilationCache.Fetched
        let sources: CargoReadSet?
        let measurement: CargoCacheMeasurement
        let replayed: CargoReplay
    }

    init(
        command: [String], environment: [String: String], arguments: [String], hookEnvironment: [String: String],
        directory: AbsolutePath, native: Bool, runner: CommandRunning, invocation: (any CargoCacheAction)?,
        recorded: CargoRecordedInvocation?, cache: CargoCompilationCache?, measurement: CargoCacheMeasurement?,
        remote: (any REAPICacheStoring)?, log: URL?, strict: Bool, flight: CargoFlight? = nil,
        verification: CargoCacheVerification.Plan? = nil
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
        self.flight = flight
        self.verification = verification
    }

    func standardOutput(_ bytes: Data) {
        if stdout.count + stderr.count + bytes.count <= 1_000_000 { stdout.append(bytes) } else { bounded = false }
    }

    /// Takes the compiler's standard error and returns it for forwarding. Cargo pipelines dependents as soon as a
    /// metadata artifact notification is forwarded, so the metadata is certified before these bytes are returned.
    func standardError(_ bytes: Data) -> Data {
        take(bytes)
        if emitted.contains("metadata") {
            // Cargo pipelines dependents as soon as this notification is forwarded. Certify
            // the atomically installed metadata first; this is admission, not cache publication.
            try? invocation?.certifyOutputs(metadataOnly: true)
        }
        return bytes
    }

    private func take(_ bytes: Data) {
        if stdout.count + stderr.count + bytes.count <= 1_000_000 { stderr.append(bytes) } else { bounded = false }
        pending.append(bytes)
        if pending.count > 1_000_000 { pending.removeAll() }
        emitted = []
        diagnostics += CargoCompilerObserver.diagnostics(
            from: &pending, remaining: 100 - diagnostics.count, emitted: &emitted
        )
    }

    /// Like Kache, a strict compilation without a usable source list is keyed once rustc has written its dep-info,
    /// right after macro expansion, rather than after it finished: when that key hits, rustc is stopped and the entry
    /// restored. Until the lookup ends, standard error is held back, so a hit's replayed messages are the only ones
    /// Cargo sees and no dependent starts from rustc's metadata. rustc writes a library's outputs itself, without a
    /// linker, so stopping it at any point leaves nothing running.
    func standardErrorUnlessCached(_ bytes: Data) -> Data? {
        if held == nil, lookup == nil, looksUp {
            looksUp = false
            // A verifying compilation must compile, never restore an entry it found meanwhile.
            if strict, cache != nil, verification == nil, (invocation as? CargoCacheInvocation)?.sourceIndex != nil {
                held = Data()
            }
        }
        guard held != nil else { return standardError(bytes) }
        take(bytes)
        held?.append(bytes)
        if emitted.contains("metadata") { heldMetadata = true }
        if lookup == nil {
            guard emitted.contains("dep-info") else { return emitted.isEmpty ? Data() : release() }
            guard let started = lookUp() else { return release() }
            lookup = started
        }
        guard let lookup else { return release() }
        // rustc writes its metadata after its dep-info: Cargo must not hear of it before the lookup ended.
        if emitted.contains("metadata") || emitted.contains("link") { lookup.done.wait() }
        guard let outcome = lookup.outcome.withLock({ $0 }) else { return Data() }
        self.lookup = nil
        if let entry = outcome {
            found = entry
            held = nil
            heldMetadata = false
            return nil
        }
        return release()
    }

    /// Ends holding standard error back, certifying metadata rustc announced meanwhile before it is forwarded.
    private func release() -> Data {
        let bytes = held ?? Data()
        held = nil
        if heldMetadata { try? invocation?.certifyOutputs(metadataOnly: true) }
        heldMetadata = false
        return bytes
    }

    /// Keys the compilation from rustc's dep-info and looks that key up, unless the key is the one that already missed.
    private func lookUp() -> Lookup? {
        guard let rust = invocation as? CargoCacheInvocation, let cache else { return nil }
        let lookup = Lookup()
        lookup.task = Task { [lookup] in
            var entry: Found?
            defer {
                lookup.outcome.withLock { $0 = .some(entry) }
                lookup.done.signal()
            }
            let (keyed, sources) = rust.refreshed()
            guard let keyed, sources != nil else { return }
            let measurement = CargoCacheMeasurement(invocation: keyed)
            let replayed = CargoReplay()
            guard var rekeyed = try? CargoCompilationCache(
                invocation: keyed, root: cache.root, remote: cache.remote, measurement: measurement
            ) else { return }
            rekeyed.replay = { replayed.stdout = $0; replayed.stderr = $1 }
            guard let fetched = try? await rekeyed.fetch() else { return }
            entry = Found(cache: rekeyed, fetched: fetched, sources: sources, measurement: measurement, replayed: replayed)
        }
        return lookup
    }

    func exited() -> Data {
        // The lookup shares the invocation's input hasher with publication, so it ends first.
        if let lookup {
            lookup.task?.cancel()
            lookup.done.wait()
            self.lookup = nil
        }
        return release()
    }

    func restore() async -> (messages: CargoReplay, publish: @Sendable () async -> Void)? {
        let entry = found
        found = nil
        // Objects are named after the dep-info file, the last output also of a metadata-only compilation.
        if let invocation = entry?.cache.invocation, let outputs = entry?.fetched.result.outputFiles.map(\.path),
           let depInfo = invocation.files.last,
           let names = try? CargoCacheInputs.entries(of: invocation.output, prefix: String(depInfo.dropLast(2)) + ".")
        {
            // rustc stopped after its metadata may have begun writing objects beside the outputs.
            for name in Set(names).subtracting(outputs) where invocation.acceptsOutput(name) {
                let file = invocation.output.appendingPathComponent(name)
                if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modified >= started { try? FileManager.default.removeItem(at: file) }
            }
        }
        guard let entry, (try? await entry.cache.install(entry.fetched)) == true else {
            // Compiled again from the start: the stopped compiler's messages and reads are incomplete.
            stdout = Data()
            stderr = Data()
            bounded = true
            diagnostics = []
            pending = Data()
            if let log { try? FileManager.default.removeItem(at: log) }
            return nil
        }
        entry.measurement.outcome(hit: true)
        return (entry.replayed, { [self] in
            if let sources = entry.sources, let rust = invocation as? CargoCacheInvocation {
                await rust.remember(sources, remote: remote)
            }
            // After the list is remembered, so a build waiting on this key finds the restored entry through it.
            flight?.release()
            entry.measurement.write()
            if let log { try? FileManager.default.removeItem(at: log) }
        })
    }

    func finish(succeeded: Bool) async {
        await settle(succeeded: succeeded)()
    }

    func abandon() async {
        abandoned = true
        await finish(succeeded: false)
    }

    func settle(succeeded: Bool) async -> @Sendable () async -> Void {
        let finished = Date()
        // A hit whose fresh compilation fails would have hidden the failure.
        if !succeeded, verification != nil {
            let finding: CargoCacheVerification.Finding = abandoned
                ? .init(check: "outputs", outcome: .failed, detail: "the compilation did not report an exit")
                : .init(check: "outputs", outcome: .content, detail: "the compilation failed, but its cached entry succeeded")
            CargoCacheVerification.report([finding], name: invocation?.name ?? "unknown", environment: hookEnvironment)
            if finding.divergent { measurement?.diverged() }
        }
        let publish = succeeded ? await admit() : nil
        let script = succeeded && !native
            && CargoCacheInputs.values("--crate-name", in: arguments).first?.hasPrefix("build_script_") == true
        // Cargo runs a build script as soon as its compilation exits, so it is stored and shimmed first: the stored
        // outputs are the compiled build script, never the shim that replaces it.
        if script {
            await publish?()
            try? await CargoBuildScript.install(
                arguments, environment: hookEnvironment, directory: directory, process: CargoProcess(runner: runner)
            )
        }
        // Cargo starts dependents only once it hears the compiler exited, so files nothing reads before the build ends
        // (the build report's compilation row, measurements) are written after.
        return { [self] in
            CargoCompilerObserver(runner: runner).record(
                arguments, environment: hookEnvironment, started: started, finished: finished, failed: !succeeded,
                diagnostics: diagnostics
            )
            if !script { await publish?() }
            flight?.release()
            measurement?.write()
            if let log { try? FileManager.default.removeItem(at: log) }
        }
    }

    /// Admits the compilation, certifying its outputs for strict dependents, and returns its publication.
    private func admit() async -> (() async -> Void)? {
        guard let root = hookEnvironment["TUIST_CARGO_CACHE_DIR"] else { return nil }
        guard bounded else {
            if verification != nil {
                CargoCacheVerification.report(
                    [.init(check: "outputs", outcome: .failed, detail: "its messages exceed what the cache keeps")],
                    name: invocation?.name ?? "unknown", environment: hookEnvironment
                )
            }
            return nil
        }
        if let verification { return await verify(verification, root: URL(fileURLWithPath: root)) }
        var refreshed = strict ? invocation : nil
        // A changed source list is remembered after Cargo hears the compiler exited: only later builds read it.
        var remember: (@Sendable () async -> Void)?
        if let rust = refreshed as? CargoCacheInvocation {
            let (keyed, sources) = rust.refreshed()
            refreshed = keyed
            if let sources { remember = { [remote] in await rust.remember(sources, remote: remote) } }
        }
        if var cache, let measurement, let refreshed {
            if refreshed.key != invocation?.key, let rekeyed = try? CargoCompilationCache(
                invocation: refreshed, root: URL(fileURLWithPath: root), remote: remote, measurement: measurement
            ) { cache = rekeyed }
            guard (try? await cache.admit(keyedAfterCompiling: refreshed.key != invocation?.key)) == true else { return remember }
            return { [self, stdout, stderr] in
                await remember?()
                do { try await cache.publish(stdout: stdout, stderr: stderr) } catch {
                    notStored(refreshed.name, "its outputs could not be stored (\(error))")
                }
            }
        }
        // Recorded outputs are never certified, so the whole publication can wait.
        return { [self] in
            await remember?()
            guard let recorded, let log, let measurement else { return }
            var reason = "its reads were not fully recorded"
            guard let finished = recorded.recorded(log: log, started: started, explain: { reason = "it \($0)" }),
                  let reads = finished.reads, let index = finished.index
            else { return notStored(recorded.name, reason) }
            // Only once the run is known to be cacheable: the session waits for this before the command returns.
            guard await finished.bundleDebugInformation(process: CargoProcess(runner: runner)) else {
                return notStored(recorded.name, "dsymutil could not bundle its debug information")
            }
            await index.put(reads, remote: remote, environment: hookEnvironment)
            do {
                try await CargoCompilationCache(
                    invocation: finished, root: URL(fileURLWithPath: root), remote: remote, measurement: measurement
                ).store(stdout: stdout, stderr: stderr, keyedAfterCompiling: true)
            } catch { notStored(recorded.name, "its outputs could not be stored (\(error))") }
        }
    }

    /// Admits a verifying compilation as any other, so strict dependents stay cacheable, and returns its comparison with
    /// the entry the hit would have restored. Nothing is published: the cache stays as it was.
    private func verify(_ plan: CargoCacheVerification.Plan, root: URL) async -> () async -> Void {
        var findings = plan.findings
        if let rust = invocation as? CargoCacheInvocation, let measurement {
            let keyed = rust.refreshed().keyed
            if let keyed, let cache = try? CargoCompilationCache(
                invocation: keyed, root: root, remote: nil, measurement: measurement
            ) {
                _ = try? await cache.admit(keyedAfterCompiling: keyed.key != rust.key)
            }
            if plan.selection.inputs, findings.isEmpty, let sources = plan.sources {
                if let fresh = rust.depInfoInputs() {
                    findings.append(CargoCacheVerification.compareSources(rust, sources: sources, fresh: fresh))
                } else {
                    findings.append(.init(check: "sources", outcome: .failed, detail: "its dep-info cannot be read"))
                }
            }
        }
        return { [self, findings] in
            var findings = findings
            if plan.selection.inputs, let used = plan.reads {
                var reason = "its reads were not fully recorded"
                if let recorded, let log,
                   let fresh = recorded.recorded(log: log, started: started, explain: { reason = "it \($0)" })?.reads
                {
                    findings.append(CargoCacheVerification.compare(used: used, fresh: fresh))
                } else {
                    findings.append(.init(check: "reads", outcome: .failed, detail: reason))
                }
            }
            if plan.selection.outputs, let invocation {
                findings.append(await CargoCacheVerification.compareOutputs(
                    plan.entry, invocation: invocation, root: root, remote: remote
                ))
            }
            CargoCacheVerification.report(findings, name: invocation?.name ?? "unknown", environment: hookEnvironment)
            if findings.contains(where: \.divergent) { measurement?.diverged() }
        }
    }

    private func notStored(_ name: String, _ reason: String) {
        if hookEnvironment["TUIST_DEBUG"] == "1" {
            FileHandle.standardError.write(Data("Tuist Cargo cache: \(name) was not stored: \(reason)\n".utf8))
        }
    }
}
