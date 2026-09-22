import Foundation
import Path
import Subprocess
#if canImport(System)
    import System
#else
    import SystemPackage
#endif

public enum CommandEvent: Sendable {
    case standardOutput([UInt8])
    case standardError([UInt8])
}

public enum CommandError: Error, Equatable, Sendable {
    case executableNotFound(String)
    case terminated(Int32, stderr: String, command: [String])
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

public protocol CommandRunning: Sendable {
    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error>
}

extension CommandRunning {
    func run(arguments: [String]) -> AsyncThrowingStream<CommandEvent, any Error> {
        run(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: nil
        )
    }
}

extension AsyncThrowingStream where Element == CommandEvent {
    func concatenatedString() async throws -> String {
        var output = ""
        for try await event in self {
            if case let .standardOutput(bytes) = event {
                output.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return output
    }
}

public struct CommandRunner: CommandRunning {
    public init() {}

    public func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: AbsolutePath? = nil
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
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
