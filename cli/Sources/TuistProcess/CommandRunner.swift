import Foundation
import Mockable
import Path
import Subprocess
import Synchronization
#if os(macOS)
    import Darwin
#endif
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

public enum ProcessEvent: Sendable {
    public enum Pipeline: Hashable, Equatable {
        case standardOutput
        case standardError
    }

    case standardOutput([UInt8])
    case standardError([UInt8])

    public var pipeline: Pipeline {
        switch self {
        case .standardOutput: .standardOutput
        case .standardError: .standardError
        }
    }

    public func string(encoding: String.Encoding = .utf8) -> String? {
        switch self {
        case let .standardOutput(bytes), let .standardError(bytes):
            String(data: Data(bytes), encoding: encoding)
        }
    }

    public var isError: Bool {
        switch self {
        case .standardError: true
        case .standardOutput: false
        }
    }
}

public typealias CommandEvent = ProcessEvent

public enum CommandError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case executableNotFound(String)
    case terminated(Int32, stderr: String, command: [String])
    case signalled(Int32, command: [String])

    public var description: String {
        switch self {
        case let .executableNotFound(executable):
            return "Couldn't locate the executable '\(executable)' in the environment."
        case let .terminated(exitCode, stderr, command):
            let commandDescription = command.joined(separator: " ")
            let trimmedStandardError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = "The command '\(commandDescription)' terminated with the code \(exitCode)"
            return trimmedStandardError.isEmpty ? description : "\(description):\n\(trimmedStandardError)"
        case let .signalled(signal, command):
            return "The command '\(command.joined(separator: " "))' terminated after receiving a signal with code \(signal)"
        }
    }

    public var errorDescription: String? { description }
}

private actor StandardErrorCollector {
    private var value = ""

    func append(_ bytes: [UInt8]) {
        value.append(String(decoding: bytes, as: UTF8.self))
    }

    func collectedValue() -> String {
        value
    }
}

private final class ProcessOutputDrain: Sendable {
    private struct State {
        var exited = false
        var stopped = false
        var incomplete = false
        var activeHandlers = 0
        var bytesAfterExit: [ProcessEvent.Pipeline: Int] = [:]
        var lastActivity = ContinuousClock.now
    }

    private let state = Mutex(State())

    func shouldStop(hasBufferedData: Bool, pipeline: ProcessEvent.Pipeline) -> Bool {
        state.withLock { state in
            if state.stopped { return true }
            guard state.exited else { return false }
            let exhausted = state.bytesAfterExit[pipeline, default: 0] >= 8_000_000
            let idle = state.activeHandlers == 0 && !hasBufferedData
                && state.lastActivity.duration(to: .now) >= .milliseconds(250)
            guard exhausted || idle else { return false }
            state.incomplete = true
            return true
        }
    }

    func forward(bytes: Int, pipeline: ProcessEvent.Pipeline, _ handler: () -> Void) {
        state.withLock { $0.activeHandlers += 1 }
        defer {
            state.withLock { state in
                state.activeHandlers -= 1
                state.lastActivity = .now
                if state.exited { state.bytesAfterExit[pipeline, default: 0] += bytes }
            }
        }
        handler()
    }

    func wait(
        stdout: AsyncThrowingStream<Never, Error>, stderr: AsyncThrowingStream<Never, Error>,
        onIncompleteOutput: @escaping @Sendable () -> Void
    ) async {
        state.withLock { state in
            state.exited = true
            state.lastActivity = .now
        }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { for try await _ in stdout {} }
                group.addTask { for try await _ in stderr {} }
                try await group.waitForAll()
            }
        } catch { state.withLock { $0.incomplete = true } }
        let incomplete = state.withLock { state in
            state.stopped = true
            return state.incomplete || Task.isCancelled
        }
        if incomplete { onIncompleteOutput() }
    }
}

@Mockable
public protocol CommandRunning: Sendable {
    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error>

    /// Backpressured output with a bounded post-exit drain; incomplete output must not be parsed.
    func runWithOutputHandler(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        onIncompleteOutput: @escaping @Sendable () -> Void,
        onOutput: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws

    /// Runs with inherited standard streams, preserving terminal detection and interactive behavior.
    func runInheritingOutput(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) async throws

    /// Runs the command in a process group of its own, which cancellation terminates as a whole, so
    /// the processes the command starts go with it. The group is not the terminal's foreground one,
    /// so an interrupt at the terminal no longer reaches the command: use it only for commands that
    /// cancellation, such as a deadline, has to stop.
    func runInOwnProcessGroup(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error>
}

extension CommandRunning {
    public func runWithOutputHandler(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        onIncompleteOutput _: @escaping @Sendable () -> Void = {},
        onOutput: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws {
        for try await event in run(arguments: arguments, environment: environment, workingDirectory: workingDirectory) {
            onOutput(event)
        }
    }

    public func runInheritingOutput(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) async throws {
        try await run(arguments: arguments, environment: environment, workingDirectory: workingDirectory)
            .pipedStream().awaitCompletion()
    }

    public func runInOwnProcessGroup(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        run(arguments: arguments, environment: environment, workingDirectory: workingDirectory)
    }

    public func run(arguments: [String]) -> AsyncThrowingStream<ProcessEvent, any Error> {
        run(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil
        )
    }

    public func run(
        arguments: [String],
        environment: [String: String]
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        run(arguments: arguments, environment: environment, workingDirectory: nil)
    }

    public func run(
        arguments: [String],
        workingDirectory: Path.AbsolutePath
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        run(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: workingDirectory
        )
    }
}

extension AsyncThrowingStream where Element == ProcessEvent {
    public func concatenatedString(
        including: Set<ProcessEvent.Pipeline> = [.standardError, .standardOutput],
        encoding: String.Encoding = .utf8
    ) async throws -> String {
        try await reduce(into: "") { output, event in
            if including.contains(event.pipeline) {
                output.append(event.string(encoding: encoding) ?? "")
            }
        }
    }

    public func pipedStream() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream<Element, Error> { continuation in
            Task {
                do {
                    for try await event in self {
                        switch event.pipeline {
                        case .standardOutput:
                            if let output = event.string(encoding: .utf8) {
                                FileHandle.standardOutput.write(Data(output.utf8))
                            }
                        case .standardError:
                            if let errorOutput = event.string(encoding: .utf8) {
                                FileHandle.standardError.write(Data(errorOutput.utf8))
                            }
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func awaitCompletion() async throws {
        for try await _ in self {}
    }
}

public struct CommandRunner: CommandRunning {
    private let processLimiter: AsyncResourceLimiter
    private let processStartedHook: (@Sendable () -> Void)?

    public init() {
        processLimiter = Self.sharedProcessLimiter
        processStartedHook = nil
    }

    init(maximumConcurrentProcesses: Int) {
        processLimiter = AsyncResourceLimiter(limit: maximumConcurrentProcesses)
        processStartedHook = nil
    }

    /// Lets tests hold the cooperative worker after spawning, before output consumption tasks can run.
    init(processStartedHook: @escaping @Sendable () -> Void) {
        processLimiter = Self.sharedProcessLimiter
        self.processStartedHook = processStartedHook
    }

    static let reservedFileDescriptors = 32
    static let fileDescriptorsPerProcess = 6
    static let maximumConcurrentProcesses = 256
    static let fallbackMaximumConcurrentProcesses = 16
    private static let gracefulShutdownDuration: Duration = .milliseconds(100)
    private static let sharedProcessLimiter = AsyncResourceLimiter(
        limitProvider: { systemMaximumConcurrentProcesses() }
    )

    public func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        run(arguments: arguments, environment: environment, workingDirectory: workingDirectory, ownProcessGroup: false)
    }

    public func runWithOutputHandler(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        onIncompleteOutput: @escaping @Sendable () -> Void = {},
        onOutput: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws {
        try await processLimiter.withPermit {
            guard let name = arguments.first else { throw CommandError.executableNotFound("") }
            var options = Self.platformOptions(environment: environment)
            options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: Self.gracefulShutdownDuration)]
            let configuration = Configuration(
                executable: name.contains("/") ? .path(FilePath(name)) : .name(name),
                arguments: Arguments(Array(arguments.dropFirst())),
                environment: .custom(Dictionary(uniqueKeysWithValues: environment.map { (
                    Environment.Key(rawValue: $0.key)!,
                    $0.value
                ) })),
                workingDirectory: workingDirectory.map { FilePath($0.pathString) }, platformOptions: options
            )
            let stdout = try FileDescriptor.pipe()
            let stderr: (readEnd: FileDescriptor, writeEnd: FileDescriptor)
            do { stderr = try FileDescriptor.pipe() } catch {
                try? stdout.readEnd.close()
                try? stdout.writeEnd.close()
                throw error
            }
            let outputWriter = FileHandle(fileDescriptor: stdout.writeEnd.rawValue, closeOnDealloc: true)
            let errorWriter = FileHandle(fileDescriptor: stderr.writeEnd.rawValue, closeOnDealloc: true)
            defer {
                try? outputWriter.close()
                try? errorWriter.close()
            }
            let drain = ProcessOutputDrain()
            let output = FileHandle(fileDescriptor: stdout.readEnd.rawValue, closeOnDealloc: true)
                .consumeOutput(shouldStop: { drain.shouldStop(hasBufferedData: $0, pipeline: .standardOutput) }) { bytes in
                    drain.forward(bytes: bytes.count, pipeline: .standardOutput) { onOutput(.standardOutput(Array(bytes))) }
                }
            let errors = FileHandle(fileDescriptor: stderr.readEnd.rawValue, closeOnDealloc: true)
                .consumeOutput(shouldStop: { drain.shouldStop(hasBufferedData: $0, pipeline: .standardError) }) { bytes in
                    drain.forward(bytes: bytes.count, pipeline: .standardError) { onOutput(.standardError(Array(bytes))) }
                }
            var executionError: Error?
            do {
                let result = try await Subprocess.run(
                    configuration, input: .standardInput,
                    output: .fileDescriptor(stdout.writeEnd, closeAfterSpawningProcess: false),
                    error: .fileDescriptor(stderr.writeEnd, closeAfterSpawningProcess: false)
                ) { _ in
                    try? outputWriter.close()
                    try? errorWriter.close()
                    processStartedHook?()
                }
                if !result.terminationStatus.isSuccess {
                    switch result.terminationStatus {
                    case let .exited(code): throw CommandError.terminated(code, stderr: "", command: arguments)
                    #if !os(Windows)
                        case let .signaled(signal): throw CommandError.signalled(signal, command: arguments)
                    #endif
                    }
                }
            } catch { executionError = error }
            try? outputWriter.close()
            try? errorWriter.close()
            await drain.wait(stdout: output, stderr: errors, onIncompleteOutput: onIncompleteOutput)
            if let executionError { throw executionError }
        }
    }

    public func runInheritingOutput(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) async throws {
        try await processLimiter.withPermit {
            guard let name = arguments.first else { throw CommandError.executableNotFound("") }
            let executable: Executable = name.contains("/") ? .path(FilePath(name)) : .name(name)
            let subprocessEnvironment = Dictionary(uniqueKeysWithValues: environment.map { (
                Environment.Key(rawValue: $0.key)!,
                $0.value
            ) })
            var options = Self.platformOptions(environment: environment)
            options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: Self.gracefulShutdownDuration)]
            let configuration = Configuration(
                executable: executable,
                arguments: Arguments(Array(arguments.dropFirst())),
                environment: .custom(subprocessEnvironment),
                workingDirectory: workingDirectory.map { FilePath($0.pathString) },
                platformOptions: options
            )
            let result = try await Subprocess.run(
                configuration,
                input: .standardInput,
                output: .standardOutput,
                error: .standardError
            )
            guard result.terminationStatus.isSuccess else {
                switch result.terminationStatus {
                case let .exited(code): throw CommandError.terminated(code, stderr: "", command: arguments)
                #if !os(Windows)
                    case let .signaled(signal): throw CommandError.signalled(signal, command: arguments)
                #endif
                }
            }
        }
    }

    public func runInOwnProcessGroup(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        run(arguments: arguments, environment: environment, workingDirectory: workingDirectory, ownProcessGroup: true)
    }

    private static func platformOptions(environment: [String: String]) -> PlatformOptions {
        var options = PlatformOptions()
        #if os(macOS)
            guard environment["TUIST_CARGO_SESSION"] != nil,
                  let flags = environment["CARGO_MAKEFLAGS"],
                  let authentication = flags.split(whereSeparator: \.isWhitespace).last(where: {
                      $0.hasPrefix("--jobserver-auth=") || $0.hasPrefix("--jobserver-fds=")
                  }),
                  let value = authentication.split(separator: "=").last else { return options }
            let descriptors = value.split(separator: ",").compactMap { Int32($0) }
            guard descriptors.count == 2, Set(descriptors).count == 2,
                  descriptors.allSatisfy({ $0 > 2 && fcntl($0, F_GETFD) != -1 }) else { return options }
            options.preSpawnProcessConfigurator = { _, actions in
                for descriptor in descriptors {
                    let result = posix_spawn_file_actions_addinherit_np(&actions, descriptor)
                    if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EINVAL) }
                }
            }
        #endif
        return options
    }

    private func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?,
        ownProcessGroup: Bool
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await processLimiter.withPermit {
                        guard let executableName = arguments.first else {
                            throw CommandError.executableNotFound("")
                        }

                        let executable: Executable = executableName.contains("/")
                            ? .path(FilePath(executableName))
                            : .name(executableName)
                        let subprocessEnvironment = Dictionary(
                            uniqueKeysWithValues: environment.map { (Environment.Key(rawValue: $0.key)!, $0.value) }
                        )
                        var platformOptions = Self.platformOptions(environment: environment)
                        platformOptions.teardownSequence = [
                            .gracefulShutDown(allowedDurationToNextStep: Self.gracefulShutdownDuration),
                        ]
                        #if !os(Windows)
                            if ownProcessGroup {
                                platformOptions.processGroupID = 0
                            }
                        #endif
                        let configuration = Configuration(
                            executable: executable,
                            arguments: Arguments(Array(arguments.dropFirst())),
                            environment: .custom(subprocessEnvironment),
                            workingDirectory: workingDirectory.map { FilePath($0.pathString) },
                            platformOptions: platformOptions
                        )
                        let standardOutputPipe = try FileDescriptor.pipe()
                        let standardErrorPipe: (readEnd: FileDescriptor, writeEnd: FileDescriptor)
                        do {
                            standardErrorPipe = try FileDescriptor.pipe()
                        } catch {
                            try? standardOutputPipe.readEnd.close()
                            try? standardOutputPipe.writeEnd.close()
                            throw error
                        }
                        let standardOutput = FileHandle(fileDescriptor: standardOutputPipe.readEnd.rawValue, closeOnDealloc: true)
                        let standardError = FileHandle(fileDescriptor: standardErrorPipe.readEnd.rawValue, closeOnDealloc: true)
                        let standardErrorCollector = StandardErrorCollector()
                        // Arm both dedicated readers before spawning. Starting them inside the consumption tasks
                        // leaves the child blocked on a full pipe when the cooperative pool is congested.
                        let standardOutputStream = standardOutput.byteStream()
                        let standardErrorStream = standardError.byteStream()
                        let result = try await Subprocess.run(
                            configuration,
                            input: .standardInput,
                            output: .fileDescriptor(standardOutputPipe.writeEnd, closeAfterSpawningProcess: true),
                            error: .fileDescriptor(standardErrorPipe.writeEnd, closeAfterSpawningProcess: true)
                        ) { execution in
                            processStartedHook?()
                            try await withTaskCancellationHandler {
                                try await withThrowingTaskGroup(of: Void.self) { group in
                                    group.addTask {
                                        for try await data in standardOutputStream {
                                            continuation.yield(.standardOutput(Array(data)))
                                        }
                                    }
                                    group.addTask {
                                        for try await data in standardErrorStream {
                                            let bytes = Array(data)
                                            await standardErrorCollector.append(bytes)
                                            continuation.yield(.standardError(bytes))
                                        }
                                    }
                                    try await group.waitForAll()
                                }
                            } onCancel: {
                                #if !os(Windows)
                                    if ownProcessGroup {
                                        try? execution.send(signal: .terminate, toProcessGroup: true)
                                    }
                                #endif
                            }
                            #if !os(Windows)
                                // Subprocess's own teardown only signals the leader. This runs before
                                // Subprocess reaps the leader, so the group's id cannot have been reused.
                                if ownProcessGroup, Task.isCancelled {
                                    await Task.detached { try? await Task.sleep(for: Self.gracefulShutdownDuration) }.value
                                    try? execution.send(signal: .kill, toProcessGroup: true)
                                }
                            #endif
                        }

                        guard result.terminationStatus.isSuccess else {
                            switch result.terminationStatus {
                            case let .exited(exitCode):
                                throw CommandError.terminated(
                                    exitCode,
                                    stderr: await standardErrorCollector.collectedValue(),
                                    command: arguments
                                )
                            #if !os(Windows)
                                case let .signaled(signal):
                                    throw CommandError.signalled(signal, command: arguments)
                            #endif
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
