import Foundation
import Mockable
import Path
import Subprocess
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

@Mockable
public protocol CommandRunning: Sendable {
    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error>
}

extension CommandRunning {
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

    public init() {
        processLimiter = Self.sharedProcessLimiter
    }

    init(maximumConcurrentProcesses: Int) {
        processLimiter = AsyncResourceLimiter(limit: maximumConcurrentProcesses)
    }

    static let reservedFileDescriptors = 32
    static let fileDescriptorsPerProcess = 6
    static let maximumConcurrentProcesses = 256
    static let fallbackMaximumConcurrentProcesses = 16
    private static let gracefulShutdownDuration: Duration = .seconds(5)
    private static let sharedProcessLimiter = AsyncResourceLimiter(
        limitProvider: { systemMaximumConcurrentProcesses() }
    )

    public func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
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
                        var platformOptions = PlatformOptions()
                        platformOptions.teardownSequence = [
                            .gracefulShutDown(allowedDurationToNextStep: Self.gracefulShutdownDuration),
                        ]
                        let configuration = Configuration(
                            executable: executable,
                            arguments: Arguments(Array(arguments.dropFirst())),
                            environment: .custom(subprocessEnvironment),
                            workingDirectory: workingDirectory.map { FilePath($0.pathString) },
                            platformOptions: platformOptions
                        )
                        let standardOutputPipe = try FileDescriptor.pipe()
                        let standardErrorPipe = try FileDescriptor.pipe()
                        let standardOutput = FileHandle(fileDescriptor: standardOutputPipe.readEnd.rawValue, closeOnDealloc: true)
                        let standardError = FileHandle(fileDescriptor: standardErrorPipe.readEnd.rawValue, closeOnDealloc: true)
                        let standardErrorCollector = StandardErrorCollector()
                        let result = try await Subprocess.run(
                            configuration,
                            input: .standardInput,
                            output: .fileDescriptor(standardOutputPipe.writeEnd, closeAfterSpawningProcess: true),
                            error: .fileDescriptor(standardErrorPipe.writeEnd, closeAfterSpawningProcess: true)
                        ) { _ in
                            try await withThrowingTaskGroup(of: Void.self) { group in
                                group.addTask {
                                    for try await data in standardOutput.byteStream() {
                                        continuation.yield(.standardOutput(Array(data)))
                                    }
                                }
                                group.addTask {
                                    for try await data in standardError.byteStream() {
                                        let bytes = Array(data)
                                        await standardErrorCollector.append(bytes)
                                        continuation.yield(.standardError(bytes))
                                    }
                                }
                                try await group.waitForAll()
                            }
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
