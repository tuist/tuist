import Basic
import Foundation
import RxSwift

public protocol Systeming {
    /// System environment.
    var env: [String: String] { get }

    /// Runs a command without collecting output nor printing anything.
    ///
    /// - Parameter arguments: Command.
    /// - Throws: An error if the command fails
    func run(_ arguments: [String]) throws

    /// Runs a command without collecting output nor printing anything.
    ///
    /// - Parameter arguments: Command.
    /// - Throws: An error if the command fails
    func run(_ arguments: String...) throws

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    func capture(_ arguments: String...) throws -> String

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    func capture(_ arguments: [String]) throws -> String

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    func capture(_ arguments: String..., verbose: Bool, environment: [String: String]) throws -> String

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    func capture(_ arguments: [String], verbose: Bool, environment: [String: String]) throws -> String

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    func runAndPrint(_ arguments: String...) throws

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    func runAndPrint(_ arguments: [String]) throws

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func runAndPrint(_ arguments: String..., verbose: Bool, environment: [String: String]) throws

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func runAndPrint(_ arguments: [String], verbose: Bool, environment: [String: String]) throws

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    ///   - redirection: Instance through which the output will be redirected.
    /// - Throws: An error if the command fails.
    func runAndPrint(_ arguments: [String], verbose: Bool, environment: [String: String], redirection: Basic.Process.OutputRedirection) throws

    /// Runs a command in the shell and wraps the standard output and error in a observable.
    /// - Parameters:
    ///   - arguments: Command.
    func observable(_ arguments: [String]) -> Observable<SystemEvent<Data>>

    /// Runs a command in the shell and wraps the standard output and error in a observable.
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    func observable(_ arguments: [String], verbose: Bool) -> Observable<SystemEvent<Data>>

    /// Runs a command in the shell and wraps the standard output and error in a observable.
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the command.
    func observable(_ arguments: [String], verbose: Bool, environment: [String: String]) -> Observable<SystemEvent<Data>>

    /// Runs a command in the shell asynchronously.
    /// When the process that triggers the command gets killed, the command continues its execution.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    func async(_ arguments: [String]) throws

    /// Runs a command in the shell asynchronously.
    /// When the process that triggers the command gets killed, the command continues its execution.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the command.
    /// - Throws: An error if the command fails.
    func async(_ arguments: [String], verbose: Bool, environment: [String: String]) throws

    /// Returns the Swift version.
    ///
    /// - Returns: Swift version.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    func swiftVersion() throws -> String?

    /// Runs /usr/bin/which passing the given tool.
    ///
    /// - Parameter name: Tool whose path will be obtained using which.
    /// - Returns: The output of running 'which' with the given tool name.
    /// - Throws: An error if which exits unsuccessfully.
    func which(_ name: String) throws -> String
}

extension ProcessResult {
    /// Throws a SystemError if the result is unsuccessful.
    ///
    /// - Throws: A SystemError.
    func throwIfErrored() throws {
        switch exitStatus {
        case let .signalled(code):
            let data = try Data(stderrOutput.dematerialize())
            throw TuistSupport.SystemError.signalled(command: command(), code: code, standardError: data)
        case let .terminated(code):
            if code != 0 {
                let data = try Data(stderrOutput.dematerialize())
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
        }
    }

    public var type: ErrorType { .abort }
}

public final class System: Systeming {
    /// Shared system instance.
    public static var shared: Systeming = System()

    /// Regex expression used to get the Swift version from the output of the 'swift --version' command.
    // swiftlint:disable:next force_try
    private static var swiftVersionRegex = try! NSRegularExpression(pattern: "Apple Swift version\\s(.+)\\s\\(.+\\)", options: [])

    /// List of variables that are accepted from the user environment.
    private static let acceptedEnvironmentVariables: [String] = [
        // Shell
        "ZSH", "SHELL",
        // User,
        "PATH", "HOME", "USER", "LANG", "NSUnbufferedIO", "LC_ALL", "LC_CTYPE",
        // Node
        "NVM_DIR",
        // Ruby
        "GEM_PATH", "RUBY_ENGINE", "GEM_ROOT", "GEM_HOME", "RUBY_ROOT", "RUBY_VERSION",
        // Xcode
        "DEVELOPER_DIR",
        // Proxy
        "HTTP_PROXY", "HTTPS_PROXY", "FTP_PROXY", "ALL_PROXY", "NO_PROXY",
    ]

    /// Environment filtering out the variables that are not defined in 'acceptedEnvironmentVariables'.
    public var env: [String: String] {
        ProcessInfo.processInfo.environment.filter { System.acceptedEnvironmentVariables.contains($0.key) }
    }

    func escaped(arguments: [String]) -> String {
        arguments.map { $0.spm_shellEscaped() }.joined(separator: " ")
    }

    // MARK: - Init

    // MARK: - Systeming

    /// Runs a command without collecting output nor printing anything.
    ///
    /// - Parameter arguments: Command.
    /// - Throws: An error if the command fails
    public func run(_ arguments: [String]) throws {
        let process = Process(arguments: arguments,
                              environment: env,
                              outputRedirection: .stream(stdout: { _ in },
                                                         stderr: { _ in }),
                              verbose: false,
                              startNewProcessGroup: false)

        logger.debug("\(escaped(arguments: arguments))")

        try process.launch()
        let result = try process.waitUntilExit()
        let output = try result.utf8Output()

        logger.debug("\(output)")

        try result.throwIfErrored()
    }

    /// Runs a command without collecting output nor printing anything.
    ///
    /// - Parameter arguments: Command.
    /// - Throws: An error if the command fails
    public func run(_ arguments: String...) throws {
        try run(arguments)
    }

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    public func capture(_ arguments: String...) throws -> String {
        try capture(arguments)
    }

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    public func capture(_ arguments: [String]) throws -> String {
        try capture(arguments, verbose: false, environment: env)
    }

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    public func capture(_ arguments: String...,
                        verbose: Bool,
                        environment: [String: String]) throws -> String {
        try capture(arguments, verbose: verbose, environment: environment)
    }

    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    public func capture(_ arguments: [String],
                        verbose: Bool,
                        environment: [String: String]) throws -> String {
        let process = Process(arguments: arguments,
                              environment: environment,
                              outputRedirection: .collect,
                              verbose: verbose,
                              startNewProcessGroup: false)

        logger.debug("\(escaped(arguments: arguments))")

        try process.launch()
        let result = try process.waitUntilExit()
        let output = try result.utf8Output()

        logger.debug("\(output)")

        try result.throwIfErrored()

        return try result.utf8Output()
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    public func runAndPrint(_ arguments: String...) throws {
        try runAndPrint(arguments)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    public func runAndPrint(_ arguments: [String]) throws {
        try runAndPrint(arguments, verbose: false, environment: env)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    public func runAndPrint(_ arguments: String...,
                            verbose: Bool,
                            environment: [String: String]) throws {
        try runAndPrint(arguments,
                        verbose: verbose,
                        environment: environment)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command arguments
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    public func runAndPrint(_ arguments: [String],
                            verbose: Bool,
                            environment: [String: String]) throws {
        try runAndPrint(arguments,
                        verbose: verbose,
                        environment: environment,
                        redirection: .none)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    ///   - redirection: Instance through which the output will be redirected.
    /// - Throws: An error if the command fails.
    public func runAndPrint(_ arguments: [String],
                            verbose: Bool,
                            environment: [String: String],
                            redirection: Basic.Process.OutputRedirection) throws {
        let process = Process(arguments: arguments,
                              environment: environment,
                              outputRedirection: .stream(stdout: { bytes in
                                  FileHandle.standardOutput.write(Data(bytes))
                                  redirection.outputClosures?.stdoutClosure(bytes)
                              }, stderr: { bytes in
                                  FileHandle.standardError.write(Data(bytes))
                                  redirection.outputClosures?.stderrClosure(bytes)
                              }), verbose: verbose,
                              startNewProcessGroup: false)

        logger.debug("\(escaped(arguments: arguments))")

        try process.launch()
        let result = try process.waitUntilExit()
        let output = try result.utf8Output()

        logger.debug("\(output)")

        try result.throwIfErrored()
    }

    public func observable(_ arguments: [String]) -> Observable<SystemEvent<Data>> {
        observable(arguments, verbose: false)
    }

    public func observable(_ arguments: [String], verbose: Bool) -> Observable<SystemEvent<Data>> {
        observable(arguments, verbose: verbose, environment: env)
    }

    public func observable(_ arguments: [String], verbose: Bool, environment: [String: String]) -> Observable<SystemEvent<Data>> {
        Observable.create { (observer) -> Disposable in
            var errorData: [UInt8] = []
            let process = Process(arguments: arguments,
                                  environment: environment,
                                  outputRedirection: .stream(stdout: { bytes in
                                      observer.onNext(.standardOutput(Data(bytes)))
                                  }, stderr: { bytes in
                                      errorData.append(contentsOf: bytes)
                                      observer.onNext(.standardError(Data(bytes)))
                                  }),
                                  verbose: verbose,
                                  startNewProcessGroup: false)
            do {
                try process.launch()
                var result = try process.waitUntilExit()
                result = ProcessResult(arguments: result.arguments,
                                       exitStatus: result.exitStatus,
                                       output: result.output,
                                       stderrOutput: result.stderrOutput.map { _ in errorData })
                try result.throwIfErrored()
                observer.onCompleted()
            } catch {
                observer.onError(error)
            }
            return Disposables.create {
                if process.launched {
                    process.signal(9) // SIGKILL
                }
            }
        }
        .subscribeOn(ConcurrentDispatchQueueScheduler(queue: DispatchQueue.global()))
    }

    /// Runs a command in the shell asynchronously.
    /// When the process that triggers the command gets killed, the command continues its execution.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    public func async(_ arguments: [String]) throws {
        try async(arguments, verbose: false, environment: env)
    }

    /// Runs a command in the shell asynchronously.
    /// When the process that triggers the command gets killed, the command continues its execution.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the command.
    /// - Throws: An error if the command fails.
    public func async(_ arguments: [String], verbose: Bool, environment: [String: String]) throws {
        let process = Process(arguments: arguments,
                              environment: environment,
                              outputRedirection: .none,
                              verbose: verbose,
                              startNewProcessGroup: true)

        logger.debug("\(escaped(arguments: arguments))")

        try process.launch()
    }

    /// Returns the Swift version.
    ///
    /// - Returns: Swift version.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    public func swiftVersion() throws -> String? {
        let output = try capture("/usr/bin/xcrun", "swift", "--version")
        let range = NSRange(location: 0, length: output.count)
        guard let match = System.swiftVersionRegex.firstMatch(in: output, options: [], range: range) else { return nil }
        return NSString(string: output).substring(with: match.range(at: 1)).spm_chomp()
    }

    /// Runs /usr/bin/which passing the given tool.
    ///
    /// - Parameter name: Tool whose path will be obtained using which.
    /// - Returns: The output of running 'which' with the given tool name.
    /// - Throws: An error if which exits unsuccessfully.
    public func which(_ name: String) throws -> String {
        try capture("/usr/bin/env", "which", name).spm_chomp()
    }
}
