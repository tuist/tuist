import Foundation
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

public struct XCResultToolOutput: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let succeeded: Bool

    public init(standardOutput: String, standardError: String, succeeded: Bool) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.succeeded = succeeded
    }
}

/// The parser invokes Xcode tools directly through Apple's `swift-subprocess` package.
/// Keeping this at the Xcode-tool boundary lets parser tests provide fixture output without
/// reintroducing a repository-wide command execution abstraction.
public typealias XCResultToolExecuting = @Sendable ([String]) async throws -> XCResultToolOutput

public func executeXCResultTool(_ arguments: [String]) async throws -> XCResultToolOutput {
    guard let executableName = arguments.first else {
        throw XCResultToolError.missingExecutable
    }

    let executable: Executable = executableName.contains("/")
        ? .path(FilePath(executableName))
        : .name(executableName)
    let result = try await Subprocess.run(
        executable,
        arguments: Arguments(Array(arguments.dropFirst())),
        output: .string(limit: .max),
        error: .string(limit: .max)
    )
    return XCResultToolOutput(
        standardOutput: result.standardOutput ?? "",
        standardError: result.standardError ?? "",
        succeeded: result.terminationStatus.isSuccess
    )
}

public enum XCResultToolError: Error, LocalizedError {
    case missingExecutable
    case terminated(command: [String], standardError: String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "The command is missing an executable name."
        case let .terminated(command, standardError):
            let description = "The command '\(command.joined(separator: " "))' terminated unsuccessfully"
            let trimmedStandardError = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedStandardError.isEmpty ? description : "\(description):\n\(trimmedStandardError)"
        }
    }
}

extension XCResultToolOutput {
    func requireSuccess(for command: [String]) throws {
        guard succeeded else {
            throw XCResultToolError.terminated(command: command, standardError: standardError)
        }
    }
}
