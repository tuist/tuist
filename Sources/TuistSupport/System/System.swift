import Foundation
import Path
import TSCBasic

extension ProcessResult {
    /// Throws a SystemError if the result is unsuccessful.
    ///
    /// - Throws: A SystemError.
    func throwIfErrored() throws {
        switch exitStatus {
        case let .signalled(code):
            let data = Data(try stderrOutput.get())
            throw TuistSupport.SystemError.signalled(command: command(), code: code, standardError: data)
        case let .terminated(code):
            if code != 0 {
                let data = Data(try stderrOutput.get())
                throw TuistSupport.SystemError.terminated(command: command(), code: code, standardError: data)
            }
        }
    }

    /// It returns the command that the process executed.
    /// If the command is executed through xcrun, then the name of the tool is returned instead.
    /// - Returns: Returns the command that the process executed.
    func command() -> String {
        let command = arguments.first!
        if command == "/usr/bin/xcrun" {
            return arguments[1]
        }
        return command
    }
}

public enum SystemError: FatalError, Equatable {
    case terminated(command: String, code: Int32, standardError: Data)
    case signalled(command: String, code: Int32, standardError: Data)
    case parseSwiftVersion(String)

    public var description: String {
        switch self {
        case let .signalled(command, code, data):
            if data.count > 0, let string = String(data: data, encoding: .utf8) {
                return "The '\(command)' was interrupted with a signal \(code) and message:\n\(string)"
            } else {
                return "The '\(command)' was interrupted with a signal \(code)"
            }
        case let .terminated(command, code, data):
            if data.count > 0, let string = String(data: data, encoding: .utf8) {
                return "The '\(command)' command exited with error code \(code) and message:\n\(string)"
            } else {
                return "The '\(command)' command exited with error code \(code)"
            }
        case let .parseSwiftVersion(output):
            return "Couldn't obtain the Swift version from the output: \(output)."
        }
    }

    public var type: ErrorType {
        switch self {
        case .signalled: return .abort
        case .parseSwiftVersion: return .bug
        case .terminated: return .abort
        }
    }
}

// swiftlint:disable:next type_body_length
public final class System: Systeming {
    /// Shared system instance.
    public static var shared: Systeming {
        _shared.value
    }

    // swiftlint:disable:next identifier_name
    static let _shared: ThreadSafe<Systeming> = ThreadSafe(System())

    /// Convenience shortcut to the environment.
    public var env: [String: String] {
        ProcessInfo.processInfo.environment
    }

    func escaped(arguments: [String]) -> String {
        arguments.map { $0.spm_shellEscaped() }.joined(separator: " ")
    }

    // MARK: - Init

    // MARK: - Systeming

    public func run(_ arguments: [String]) throws {
        _ = try capture(arguments)
    }

    public func capture(_ arguments: [String]) throws -> String {
        try capture(arguments, verbose: false, environment: env)
    }

    public func capture(
        _ arguments: [String],
        verbose: Bool,
        environment: [String: String]
    ) throws -> String {
        let process = Process(
            arguments: arguments,
            environment: environment,
            outputRedirection: .collect,
            startNewProcessGroup: false,
            loggingHandler: verbose ? { stdoutStream.send($0).send("\n").flush() } : nil
        )

        logger.debug("\(escaped(arguments: arguments))")

        try process.launch()
        let result = try process.waitUntilExit()
        let output = try result.utf8Output()

        logger.debug("\(output)")

        try result.throwIfErrored()

        return try result.utf8Output()
    }

    public func runAndPrint(_ arguments: [String]) throws {
        try run(arguments, verbose: false, environment: env, redirection: streamToStandardOutputs)
    }

    public func runAndPrint(_ arguments: [String], verbose: Bool, environment: [String: String]) throws {
        try run(arguments, verbose: verbose, environment: environment, redirection: streamToStandardOutputs)
    }

    private var streamToStandardOutputs: TSCBasic.Process.OutputRedirection {
        return .stream { bytes in
            FileHandle.standardOutput.write(Data(bytes))
        } stderr: { bytes in
            FileHandle.standardError.write(Data(bytes))
        }
    }

    public func runAndCollectOutput(_ arguments: [String]) async throws -> SystemCollectedOutput {
        let process = Process(
            arguments: arguments,
            environment: env,
            outputRedirection: .collect,
            startNewProcessGroup: false
        )

        try process.launch()

        let result = try await process.waitUntilExit()

        return SystemCollectedOutput(
            standardOutput: try result.utf8Output(),
            standardError: try result.utf8stderrOutput()
        )
    }

    public func async(_ arguments: [String]) throws {
        let process = Process(
            arguments: arguments,
            environment: env,
            outputRedirection: .none,
            startNewProcessGroup: true
        )

        logger.debug("\(escaped(arguments: arguments))")

        try process.launch()
    }

    public func which(_ name: String) throws -> String {
        try capture(["/usr/bin/env", "which", name]).spm_chomp()
    }

    // MARK: Helpers

    public func chmod(
        _ mode: FileMode,
        path: Path.AbsolutePath,
        options: Set<FileMode.Option>
    ) throws {
        try localFileSystem.chmod(mode, path: .init(validating: path.pathString), options: options)
    }

    public func run(
        _ arguments: [String],
        verbose: Bool = false,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        redirection: TSCBasic.Process.OutputRedirection = .none
    ) throws {
        // We have to collect both stderr and stdout because we want to stream the output
        // the `ProcessResult` type will not contain either unless outputRedirection is set to `.collect`
        var stdErrData: [UInt8] = []

        let process = Process(
            arguments: arguments,
            environment: environment,
            outputRedirection: .stream(stdout: { bytes in
                redirection.outputClosures?.stdoutClosure(bytes)
            }, stderr: { bytes in
                stdErrData.append(contentsOf: bytes)
                redirection.outputClosures?.stderrClosure(bytes)
            }),
            startNewProcessGroup: false,
            loggingHandler: verbose ? { stdoutStream.send($0).send("\n").flush() } : nil
        )

        logger.debug("\(escaped(arguments: arguments))")

        try process.launch()
        let result = try process.waitUntilExit()

        switch result.exitStatus {
        case let .signalled(code):
            let data = Data(stdErrData)
            throw TuistSupport.SystemError.signalled(command: result.command(), code: code, standardError: data)
        case let .terminated(code):
            if code != 0 {
                let data = Data(stdErrData)
                throw TuistSupport.SystemError.terminated(command: result.command(), code: code, standardError: data)
            }
        }
    }
}
