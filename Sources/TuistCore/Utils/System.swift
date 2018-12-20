import Basic
import Foundation

public protocol Systeming {
    
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
    func popen(_ arguments: String...) throws
    
    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    func popen(_ arguments: [String]) throws
    
    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func popen(_ arguments: String..., verbose: Bool, environment: [String: String]) throws

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    func popen(_ arguments: [String], verbose: Bool, environment: [String: String]) throws

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
        return stderror ?? "Command exited with code \(exitcode)"
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
    
    /// Runs a command without collecting output nor printing anything.
    ///
    /// - Parameter arguments: Command.
    /// - Throws: An error if the command fails
    public func run(_ arguments: [String]) throws {
        let process = Process(arguments: arguments,
                              environment: System.userEnvironment,
                              outputRedirection: .none,
                              verbose: false,
                              startNewProcessGroup: false)
        try process.launch()
        try process.waitUntilExit()
    }

    /// Runs a command without collecting output nor printing anything.
    ///
    /// - Parameter arguments: Command.
    /// - Throws: An error if the command fails
    public func run(_ arguments: String...) throws {
        try self.run(arguments)
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
        return try self.capture(arguments)
    }
    
    /// Runs a command in the shell and returns the standard output string.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Returns: Standard output string.
    /// - Throws: An error if the command fails.
    public func capture(_ arguments: [String]) throws -> String {
        return try self.capture(arguments, verbose: false, environment: System.userEnvironment)
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
        return try capture(arguments, verbose: verbose)
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
                        verbose: Bool = false,
                        environment: [String: String] = System.userEnvironment) throws -> String {
        let process = Process(arguments: arguments,
                              environment: environment,
                              outputRedirection: .collect,
                              verbose: verbose,
                              startNewProcessGroup: false)
        try process.launch()
        let result = try process.waitUntilExit()
        return try result.utf8Output()
    }
    
    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    public func popen(_ arguments: String...) throws {
        try self.popen(arguments)
    }
    
    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    public func popen(_ arguments: [String]) throws {
        try self.popen(arguments, verbose: false, environment: System.userEnvironment)
    }

    /// Runs a command in the shell printing its output.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to be passed.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - workingDirectoryPath: The working directory path the task is executed from.
    ///   - environment: Environment that should be used when running the task.
    /// - Throws: An error if the command fails.
    public func popen(_ arguments: String...,
                      verbose: Bool,
                      environment: [String: String]) throws {
        try popen(arguments,
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
    public func popen(_ arguments: [String],
                      verbose: Bool = false,
                      environment: [String: String] = System.userEnvironment) throws {
        let process = Process(arguments: arguments,
                              environment: environment,
                              outputRedirection: .stream(stdout: { (bytes) in
                                FileHandle.standardOutput.write(Data(bytes: bytes))
                              }, stderr: { (bytes) in
                                FileHandle.standardError.write(Data(bytes: bytes))
                              }), verbose: verbose,
                                  startNewProcessGroup: false)
        try process.launch()
        try process.waitUntilExit()
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
        return try capture("/usr/bin/env", "which", name)
    }
}
