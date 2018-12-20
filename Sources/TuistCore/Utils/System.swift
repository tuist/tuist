import Basic
import Foundation
import SwiftShell

public protocol Systeming {
    /// Runs a command in the shell and returns the result (exit status, standard output and standard error).
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    func capture(_ launchPath: String, arguments: String..., verbose: Bool, workingDirectoryPath: AbsolutePath?, environment: [String: String]?) throws -> SystemResult

    /// Runs a command in the shell and returns the result (exit status, standard output and standard error).
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    func capture(_ launchPath: String, arguments: [String], verbose: Bool, workingDirectoryPath: AbsolutePath?, environment: [String: String]?) throws -> SystemResult

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func popen(_ launchPath: String, arguments: String..., verbose: Bool, workingDirectoryPath: AbsolutePath?, environment: [String: String]?) throws

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func popen(_ launchPath: String, arguments: [String], verbose: Bool, workingDirectoryPath: AbsolutePath?, environment: [String: String]?) throws

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
    let exitcode: Int

    public var type: ErrorType {
        return .abort
    }

    public var description: String {
        return stderror ?? "Error running command"
    }

    public init(stderror: String? = nil, exitcode: Int) {
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
    public let exitcode: Int
    public var succeeded: Bool { return exitcode == 0 }

    public init(stdout: String, stderror: String, exitcode: Int) {
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
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    @discardableResult
    public func capture(_ launchPath: String,
                        arguments: String...,
                        verbose: Bool = false,
                        workingDirectoryPath _: AbsolutePath? = nil,
                        environment: [String: String]? = System.userEnvironment) throws -> SystemResult {
        return try capture(launchPath, arguments: arguments, verbose: verbose, environment: environment)
    }

    /// Runs a command in the shell and returns the result (exit status, standard output and standard error).
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: Result of running the command.
    /// - Throws: An error if the command fails.
    @discardableResult
    public func capture(_ launchPath: String,
                        arguments: [String],
                        verbose: Bool = false,
                        workingDirectoryPath: AbsolutePath? = nil,
                        environment: [String: String]? = System.userEnvironment) throws -> SystemResult {
        if verbose {
            printCommand(launchPath, arguments: arguments)
        }
        let context = self.context(workingDirectoryPath: workingDirectoryPath, environment: environment)
        let result = context.run(launchPath, arguments, combineOutput: false)
        return SystemResult(stdout: result.stdout, stderror: result.stderror, exitcode: result.exitcode)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    public func popen(_ launchPath: String,
                      arguments: String...,
                      verbose: Bool = false,
                      workingDirectoryPath: AbsolutePath? = nil,
                      environment: [String: String]? = System.userEnvironment) throws {
        try popen(launchPath,
                  arguments: arguments,
                  verbose: verbose,
                  workingDirectoryPath: workingDirectoryPath,
                  environment: environment)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - launchPath: Path to the binary or script to run.
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    public func popen(_ launchPath: String,
                      arguments: [String],
                      verbose: Bool = false,
                      workingDirectoryPath: AbsolutePath? = nil,
                      environment: [String: String]? = System.userEnvironment) throws {
        if verbose {
            printCommand(launchPath, arguments: arguments)
        }
        let context = self.context(workingDirectoryPath: workingDirectoryPath, environment: environment)
        try context.runAndPrint(launchPath, arguments)
    }

    /// Creates the context to run the command
    ///
    /// - Parameters:
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Returns: The context to run the command on.
    public func context(workingDirectoryPath: AbsolutePath?,
                        environment: [String: String]?) -> CustomContext {
        var context = CustomContext(main)
        if let workingDirectoryPath = workingDirectoryPath {
            context.currentdirectory = workingDirectoryPath.asString
        }
        if let environment = environment {
            context.env = environment
        }
        return context
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
