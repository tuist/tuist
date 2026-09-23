import Foundation

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

/// The parser invokes Xcode tools at this boundary so parser tests can provide fixture output.
public typealias XCResultToolExecuting = @Sendable ([String]) async throws -> XCResultToolOutput

public func executeXCResultTool(_ arguments: [String]) async throws -> XCResultToolOutput {
    guard let executableName = arguments.first else {
        throw XCResultToolError.missingExecutable
    }

    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: errorURL)
    }

    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let errorHandle = try FileHandle(forWritingTo: errorURL)
    defer {
        try? outputHandle.close()
        try? errorHandle.close()
    }

    let process = XCResultToolProcess()
    if executableName.contains("/") {
        process.process.executableURL = URL(fileURLWithPath: executableName)
        process.process.arguments = Array(arguments.dropFirst())
    } else {
        process.process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.process.arguments = arguments
    }
    process.process.standardOutput = outputHandle
    process.process.standardError = errorHandle
    try await process.run()

    return XCResultToolOutput(
        standardOutput: try String(contentsOf: outputURL, encoding: .utf8),
        standardError: try String(contentsOf: errorURL, encoding: .utf8),
        succeeded: process.process.terminationStatus == 0
    )
}

private final class XCResultToolProcess: @unchecked Sendable {
    let process = Process()

    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { _ in
                    continuation.resume()
                }

                do {
                    try process.run()
                    if Task.isCancelled, process.isRunning {
                        process.terminate()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
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
