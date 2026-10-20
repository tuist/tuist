import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistProcess
import TuistServer

struct CargoExecutionContext {
    let executable: String
    let directory: AbsolutePath
    let arguments: [String]
    let environment: [String: String]
    let reporting: CargoReporting
}

public struct CargoCommandService {
    private let runner: CommandRunning
    public init(runner: CommandRunning = CommandRunner()) { self.runner = runner }

    public func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        directory: AbsolutePath? = nil
    ) async throws {
        var environment = environment
        let directory = try directory ?? AbsolutePath(validating: FileManager.default.currentDirectoryPath)
        let invocation = CargoInvocation(arguments)
        if let toolchain = invocation.toolchain { environment["RUSTUP_TOOLCHAIN"] = toolchain }
        if arguments.first == "__compiler" {
            try await CargoCompilerObserver(runner: runner).run(
                Array(arguments.dropFirst()),
                environment: environment,
                directory: directory
            )
            return
        }
        let process = CargoProcess(runner: runner)
        let resolved = try await process.executable(invocation: invocation, environment: environment, directory: directory)
        let executable = resolved.path
        // A rustup proxy pins its selection before Cargo changes directories to compile workspace members.
        if let toolchain = resolved.toolchain { environment["RUSTUP_TOOLCHAIN"] = toolchain }
        try Task.checkCancellation()
        let isSharding = invocation.command == "test-build" || environment["TUIST_SHARD_INDEX"] != nil
        try validateShardingDirectory(invocation: invocation, isSharding: isSharding)
        if environment["TUIST_CARGO_ACTIVE"] == nil, invocation.observesBuild {
            do {
                if let context = try await context(
                    executable: executable,
                    invocation: invocation,
                    directory: directory,
                    environment: environment
                ) {
                    try await decorate(context)
                    return
                }
            } catch let error as CommandError {
                throw error
            } catch {
                if isSharding || Task.isCancelled || error is CancellationError { throw error }
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
        if invocation.changesDirectory, invocation.command == "test-build" || (invocation.isNextestRun && isSharding),
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
        environment: [String: String]
    ) async throws -> CargoExecutionContext? {
        let config = try? await ConfigLoader().loadCargoConfig(path: directory)
        guard let handle = environment["TUIST_PROJECT"] ?? config?.fullHandle else {
            if invocation.command == "test-build" || environment["TUIST_SHARD_INDEX"] != nil {
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
        let metadata = await context.reporting.metadata()
        let innerWrapper = try CargoConfiguration.compilerWrapper(
            directory: URL(fileURLWithPath: context.directory.pathString),
            arguments: context.arguments,
            environment: context.environment
        )
        try await FileSystem().runInTemporaryDirectory(prefix: "tuist-cargo") { temporary in
            let root = URL(fileURLWithPath: temporary.pathString)
            let started = Date()
            var environment = context.environment
            environment["TUIST_CARGO_ACTIVE"] = "1"
            environment["TUIST_CARGO_SESSION"] = root.path
            environment["TUIST_CARGO_STARTED"] = String(started.timeIntervalSince1970)
            environment["TUIST_CARGO_INNER_WRAPPER"] = innerWrapper
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            let configured = CargoExecutionContext(
                executable: context.executable, directory: context.directory, arguments: context.arguments,
                environment: environment, reporting: context.reporting
            )
            let native = await CargoCacheRuntime(process: context.reporting.process).prepare(configured, root: root)
            let cache = native == nil ? await CargoCacheSetup().prepare(configured, root: root) : nil
            defer {
                native?.cancel()
                cache?.refresh?.cancel()
            }
            if let native { environment = native.environment } else if let cache { environment = cache.environment }
            if native == nil, innerWrapper == nil {
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
            let child = CargoExecutionContext(
                executable: native?.executable ?? context.executable,
                directory: context.directory,
                arguments: context.arguments,
                environment: environment,
                reporting: context.reporting
            )
            try await executeSession(child, root: root, started: started, metadata: metadata)
        }
    }

    private func executeSession(
        _ context: CargoExecutionContext,
        root: URL,
        started: Date,
        metadata: [String: Any]
    ) async throws {
        let invocation = CargoInvocation(context.arguments)
        var executionError: Error?
        var nextest: CargoNextestRun?
        do {
            if invocation.command == "test-build" {
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
                } else if context.environment["TUIST_SHARD_INDEX"] != nil {
                    throw CargoReportError(message: "Rust shards require 'tuist cargo nextest run'.")
                }
                try await context.reporting.process.execute(
                    context.executable,
                    arguments: nextest?.arguments ?? context.arguments,
                    environment: context.environment,
                    directory: context.directory
                )
            }
        } catch { executionError = error }
        if invocation.reportsBuild {
            await context.reporting.build(
                root: root,
                started: started,
                command: invocation.command ?? "",
                metadata: metadata,
                failed: executionError != nil
            )
        }
        if let nextest { await context.reporting.tests(run: nextest, metadata: metadata, failed: executionError != nil) }
        if let executionError { throw executionError }
    }

    static func milliseconds(_ seconds: Double) -> Int { Int(min(max((seconds * 1000).rounded(), 0), Double(UInt32.max))) }
    static func listArguments(_ arguments: [String]) -> [String] { CargoNextestService.listArguments(arguments) }
}
