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

public enum CommandError: Error, Equatable, Sendable, CustomStringConvertible {
    case executableNotFound(String)
    case terminated(Int32, stderr: String, command: [String])

    public var description: String {
        switch self {
        case let .executableNotFound(executable):
            "Executable not found: \(executable)"
        case let .terminated(exitCode, stderr, command):
            let commandDescription = command.joined(separator: " ")
            return stderr.isEmpty
                ? "Command terminated with exit code \(exitCode): \(commandDescription)"
                : "Command terminated with exit code \(exitCode): \(commandDescription)\n\(stderr)"
        }
    }
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
    public init() {}

    public func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<ProcessEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let executableName = arguments.first else {
                        throw CommandError.executableNotFound("")
                    }

                    let executable: Executable = executableName.contains("/")
                        ? .path(FilePath(executableName))
                        : .name(executableName)
                    let subprocessEnvironment = Dictionary(
                        uniqueKeysWithValues: environment.map { (Environment.Key(rawValue: $0.key)!, $0.value) }
                    )
                    let configuration = Configuration(
                        executable: executable,
                        arguments: Arguments(Array(arguments.dropFirst())),
                        environment: .custom(subprocessEnvironment),
                        workingDirectory: workingDirectory.map { FilePath($0.pathString) }
                    )
                    let standardError = StandardErrorCollector()
                    let result = try await Subprocess.run(configuration) { _, _, output, error in
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                for try await buffer in output {
                                    continuation.yield(.standardOutput(buffer.withUnsafeBytes(Array.init)))
                                }
                            }
                            group.addTask {
                                for try await buffer in error {
                                    let bytes = buffer.withUnsafeBytes(Array.init)
                                    await standardError.append(bytes)
                                    continuation.yield(.standardError(bytes))
                                }
                            }
                            try await group.waitForAll()
                        }
                    }

                    guard result.terminationStatus.isSuccess else {
                        let exitCode: Int32
                        switch result.terminationStatus {
                        case let .exited(code): exitCode = code
                        #if !os(Windows)
                            case let .signaled(signal): exitCode = signal
                        #endif
                        }
                        throw CommandError.terminated(
                            exitCode,
                            stderr: await standardError.collectedValue(),
                            command: arguments
                        )
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
