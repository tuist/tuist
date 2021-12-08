import Foundation
import TSCBasic

public final class Tuist {
    enum TuistError: Error {
        case signalled(command: String, code: Int32, standardError: Data)
        case terminated(command: String, code: Int32, standardError: Data)
        case invalidData
        
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
            case .invalidData:
                return "Invalid data returned tuist graph command"
            }
        }
    }
    
    public static func graph() throws -> Graph {
        // If a task is executed via `tuist`, it gets passed the binary path as a last argument.
        // Otherwise, fallback to go
        let tuistBinaryPath = ProcessInfo.processInfo.environment["TUIST_CONFIG_BINARY_PATH"] ?? "tuist"
        guard
            let graphOutput = try capture([tuistBinaryPath, "graph", "--format", "json"]).data(using: .utf8)
        else { throw TuistError.invalidData }
        return try JSONDecoder().decode(Graph.self, from: graphOutput)
    }
    
    private static func capture(
        _ arguments: [String]
    ) throws -> String {
        let process = Process(
            arguments: arguments,
            outputRedirection: .collect,
            startNewProcessGroup: false
        )

        try process.launch()
        let result = try process.waitUntilExit()

        try result.throwIfErrored()

        return try result.utf8Output()
    }
}

extension ProcessResult {
    /// Throws a SystemError if the result is unsuccessful.
    ///
    /// - Throws: A SystemError.
    func throwIfErrored() throws {
        switch exitStatus {
        case let .signalled(code):
            let data = Data(try stderrOutput.get())
            throw Tuist.TuistError.signalled(command: command(), code: code, standardError: data)
        case let .terminated(code):
            if code != 0 {
                let data = Data(try stderrOutput.get())
                throw Tuist.TuistError.terminated(command: command(), code: code, standardError: data)
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
