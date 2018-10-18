import Basic
import Foundation
import ReactiveSwift
import ReactiveTask

public protocol Systeming {
    /// Runs a command in the shell and returns the result (exit status, standard output and standard error).
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    func capture(_ launchPath: String, arguments: String..., verbose: Bool, environment: [String: String]?) throws -> SystemResult

    /// Runs a command in the shell and returns the result (exit status, standard output and standard error).
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    func capture(_ launchPath: String, arguments: [String], verbose: Bool, environment: [String: String]?) throws -> SystemResult

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func popen(_ launchPath: String, arguments: String..., verbose: Bool, environment: [String: String]?) throws

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func popen(_ launchPath: String, arguments: [String], verbose: Bool, environment: [String: String]?) throws

    /// Instantiates a SignalProducer that launches the given path.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - print: When true, it outputs the output from the execution.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: SignalProducer that encapsulates the task action.
    func task(_ launchPath: String,
              arguments: [String],
              print: Bool,
              environment: [String: String]?) -> SignalProducer<TaskEvent<Data>, SystemError>

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

public struct SystemError: FatalError, Equatable {
    let stderror: String?
    let exitcode: Int32

    public var type: ErrorType {
        return .abort
    }

    public var description: String {
        return stderror ?? "Error running command"
    }

    public init(stderror: String? = nil, exitcode: Int32) {
        self.stderror = stderror
        self.exitcode = exitcode
    }

    public static func == (lhs: SystemError, rhs: SystemError) -> Bool {
        return lhs.stderror == rhs.stderror &&
            lhs.exitcode == rhs.exitcode
    }
}

public struct SystemResult {
    public let stdout: String
    public let stderror: String
    public let exitcode: Int32
    public init(stdout: String, stderror: String, exitcode: Int32) {
        self.stdout = stdout
        self.stderror = stderror
        self.exitcode = exitcode
    }

    @discardableResult
    public func throwIfError() throws -> SystemResult {
        if exitcode != 0 { throw SystemError(stderror: stderror, exitcode: exitcode) }
        return self
    }
}

public final class System: Systeming {
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
    ]

    // MARK: - Init

    /// Default constructor.
    public init() {}

    // MARK: - Systeming

    /// User environment filtering out the variables that are not defined in 'acceptedEnvironmentVariables'.
    public static var userEnvironment: [String: String] {
        return ProcessInfo.processInfo.environment.filter({ acceptedEnvironmentVariables.contains($0.key) })
    }

    /// Runs a command in the shell and returns the result (exit status, standard output and standard error).
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    @discardableResult
    public func capture(_ launchPath: String,
                        arguments: String...,
                        verbose: Bool = false,
                        environment: [String: String]? = System.userEnvironment) throws -> SystemResult {
        return try capture(launchPath, arguments: arguments, verbose: verbose, environment: environment)
    }

    /// Runs a command in the shell and returns the result (exit status, standard output and standard error).
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    @discardableResult
    public func capture(_ launchPath: String,
                        arguments: [String],
                        verbose: Bool = false,
                        environment: [String: String]? = System.userEnvironment) throws -> SystemResult {
        if verbose {
            printCommand(launchPath, arguments: arguments)
        }
        let task: SignalProducer<SystemResult, SystemError> = self.task(launchPath,
                                                                        arguments: arguments,
                                                                        print: false,
                                                                        environment: environment)
            .ignoreTaskData()
            .map { data in
                let stdout = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "\n", with: "").chomp()
                return SystemResult(stdout: stdout, stderror: "", exitcode: 0)
            }
        if let output = task.single() {
            return try output.dematerialize()
        } else {
            throw SystemError(stderror: "Error running command: \(commandString(launchPath, arguments: arguments))", exitcode: 1)
        }
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    public func popen(_ launchPath: String,
                      arguments: String...,
                      verbose: Bool = false,
                      environment: [String: String]? = System.userEnvironment) throws {
        try popen(launchPath, arguments: arguments, verbose: verbose, environment: environment)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    public func popen(_ launchPath: String,
                      arguments: [String],
                      verbose: Bool = false,
                      environment: [String: String]? = System.userEnvironment) throws {
        if verbose {
            printCommand(launchPath, arguments: arguments)
        }
        _ = task(launchPath, arguments: arguments, print: true, environment: environment).wait()
    }

    /// Instantiates a SignalProducer that launches the given path.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - print: When true, it outputs the output from the execution.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: SignalProducer that encapsulates the task action.
    public func task(_ launchPath: String,
                     arguments: [String],
                     print: Bool = false,
                     environment: [String: String]? = nil) -> SignalProducer<TaskEvent<Data>, SystemError> {
        let task = Task(launchPath, arguments: arguments, workingDirectoryPath: nil, environment: environment)
        return task.launch()
            .on(value: {
                if !print { return }
                switch $0 {
                case let .standardError(error):
                    FileHandle.standardError.write(error)
                case let .standardOutput(output):
                    FileHandle.standardOutput.write(output)
                default:
                    break
                }
            })
            .mapError { (error: TaskError) -> SystemError in
                switch error {
                case let TaskError.posixError(code):
                    return SystemError(stderror: nil, exitcode: code)
                case let TaskError.shellTaskFailed(_, code, standardError):
                    return SystemError(stderror: standardError, exitcode: code)
                }
            }
    }

    /// Returns the Swift version.
    ///
    /// - Returns: Swift version.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    public func swiftVersion() throws -> String? {
        let output = try capture("/usr/bin/xcrun", arguments: "swift", "--version", verbose: false, environment: nil).throwIfError().stdout
        let range = NSRange(location: 0, length: output.count)
        guard let match = System.swiftVersionRegex.firstMatch(in: output, options: [], range: range) else { return nil }
        return NSString(string: output).substring(with: match.range(at: 1)).chomp()
    }

    /// Runs /usr/bin/which passing the given tool.
    ///
    /// - Parameter name: Tool whose path will be obtained using which.
    /// - Returns: The output of running 'which' with the given tool name.
    /// - Throws: An error if which exits unsuccessfully.
    public func which(_ name: String) throws -> String {
        return try capture("/usr/bin/env", arguments: "which", name).throwIfError().stdout
    }

    // MARK: - Fileprivate

    /// Prints the given command.
    ///
    /// - Parameters:
    ///   - launchPath: Launch path.
    ///   - arguments: Arguments passed to the task.
    fileprivate func printCommand(_ launchPath: String, arguments: [String]) {
        let output = "Running: \(commandString(launchPath, arguments: arguments))"
        if let data = output.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }

    /// Returns a string with the launch path and arguments joined with a space in between.
    ///
    /// - Parameters:
    ///   - launchPath: Launch path.
    ///   - arguments: Arguments passed to the task.
    /// - Returns: String with the launch path and arguments joined with a space in between.
    fileprivate func commandString(_ launchPath: String, arguments: [String]) -> String {
        var arguments = arguments
        arguments.insert(launchPath, at: 0)
        return arguments.joined(separator: " ")
    }
}
