import Basic
import Foundation
import Utility

/// Shell error.
struct ShellError: FatalError, Equatable {
    let description: String

    var type: ErrorType {
        return .abort
    }
}

/// Protocol that represents a shell interface.
public protocol Shelling: AnyObject {
    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    func run(_ args: String..., environment: [String: String]) throws -> String

    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    func run(_ args: [String], environment: [String: String]) throws -> String
}

/// Default implementation of Shelling.
public class Shell: Shelling {
    /// Default constructor.
    public init() {}

    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    public func run(_ args: String..., environment: [String: String] = [:]) throws -> String {
        return try run(args, environment: environment)
    }

    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    public func run(_ args: [String], environment: [String: String] = [:]) throws -> String {
        let result = try Process.popen(arguments: args, environment: environment)
        if result.exitStatus == .terminated(code: 0) {
            return try result.utf8Output()
        } else {
            throw ShellError(description: try result.utf8stderrOutput())
        }
    }
}
