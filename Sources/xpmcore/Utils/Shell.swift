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
    /// Runs a shell command synchronously
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    func run(_ args: String..., environment: [String: String]) throws

    /// Runs a shell command synchronously
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    func run(_ args: [String], environment: [String: String]) throws

    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    func runAndOutput(_ args: String..., environment: [String: String]) throws -> String

    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    func runAndOutput(_ args: [String], environment: [String: String]) throws -> String
}

/// Default implementation of Shelling.
public class Shell: Shelling {
    /// Default constructor.
    public init() {}

    /// Runs a shell command synchronously
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    public func run(_ args: String..., environment: [String: String] = [:]) throws {
        try run(args, environment: environment)
    }

    /// Runs a shell command synchronously
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    public func run(_ args: [String], environment: [String: String] = [:]) throws {
        let process = Process(arguments: args, environment: environment, redirectOutput: false)
        try process.launch()
        let result = try process.waitUntilExit()
        if result.exitStatus != .terminated(code: 0) {
            let arg = args.first ?? ""
            throw ShellError(description: "There was an error running \"\(arg)\". The logs above include details about the error.")
        }
    }

    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    public func runAndOutput(_ args: String..., environment: [String: String] = [:]) throws -> String {
        return try runAndOutput(args, environment: environment)
    }

    /// Runs a shell command synchronously and returns the output.
    ///
    /// - Parameters:
    /// - Parameter args: shell command to be run.
    ///   - environment: environment.
    /// - Returns: the command output.
    /// - Throws: an error if the execution fails.
    public func runAndOutput(_ args: [String], environment: [String: String] = [:]) throws -> String {
        let process = Process(arguments: args, environment: environment, redirectOutput: true)
        try process.launch()
        let result = try process.waitUntilExit()
        if result.exitStatus == .terminated(code: 0) {
            return try result.utf8Output()
        } else {
            throw ShellError(description: try result.utf8stderrOutput())
        }
    }
}
