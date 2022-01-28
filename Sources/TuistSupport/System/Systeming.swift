import Combine
import Foundation
import TSCBasic

public protocol Systeming {
    /// System environment.
    var env: [String: String] { get }

    /// Runs a command without collecting output nor printing anything.
    ///
    /// - Parameter arguments: Command.
    /// - Throws: An error if the command fails
    func run(_ arguments: [String]) throws

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
    func capture(_ arguments: [String], verbose: Bool, environment: [String: String]) throws -> String

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
    func runAndPrint(_ arguments: [String], verbose: Bool, environment: [String: String]) throws

    /// Runs a command in the shell and wraps the standard output.
    /// - Parameters:
    ///   - arguments: Command.
    func runAndCollectOutput(_ arguments: [String]) async throws -> SystemCollectedOutput

    /// Runs a command in the shell and wraps the standard output and error in a publisher.
    /// - Parameters:
    ///   - arguments: Command.
    func publisher(_ arguments: [String]) -> AnyPublisher<SystemEvent<Data>, Error>

    /// Runs a command in the shell and wraps the standard output and error in a publisher.
    /// - Parameters:
    ///   - arguments: Command.
    ///   - verbose: When true it prints the command that will be executed before executing it.
    ///   - environment: Environment that should be used when running the command.
    func publisher(_ arguments: [String], verbose: Bool, environment: [String: String]) -> AnyPublisher<SystemEvent<Data>, Error>

    /// Runs a command in the shell and wraps the standard output and error in a publisher.
    /// - Parameters:
    ///   - arguments: Command.
    ///   - pipeTo: Second Command.
    func publisher(_ arguments: [String], pipeTo secondArguments: [String]) -> AnyPublisher<SystemEvent<Data>, Error>

    /// Runs a command in the shell asynchronously.
    /// When the process that triggers the command gets killed, the command continues its execution.
    ///
    /// - Parameters:
    ///   - arguments: Command.
    /// - Throws: An error if the command fails.
    func async(_ arguments: [String]) throws

    /// Returns the Swift version.
    ///
    /// - Returns: Swift version.
    /// - Throws: An error if Swift is not installed or it exists unsuccessfully.
    func swiftVersion() throws -> String

    /// Runs /usr/bin/which passing the given tool.
    ///
    /// - Parameter name: Tool whose path will be obtained using which.
    /// - Returns: The output of running 'which' with the given tool name.
    /// - Throws: An error if which exits unsuccessfully.
    func which(_ name: String) throws -> String

    /// Changes permissions for a given file at `path`
    /// - Parameters:
    ///     - mode: Defines user file mode.
    ///     - path: Path of file for which the permissions should be changed.
    ///     - options: Options for changing permissions.
    func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws
}

extension Systeming {
    public func commandExists(_ name: String) -> Bool {
        do {
            _ = try which(name)
            return true
        } catch {
            return false
        }
    }
}
