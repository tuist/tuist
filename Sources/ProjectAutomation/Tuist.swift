import Foundation
import TSCBasic

/// Tuist includes all methods to interact with your tuist project
public enum Tuist {
    enum TuistError: Error {
        case signalled(command: String, code: Int32, standardError: Data)
        case terminated(command: String, code: Int32, standardError: Data)

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
    }

    /// Loads and returns the graph at the given path.
    /// - parameter path: the path which graph should be loaded. If nil, the current path is used.
    /// - parameter environmentKeys: the environment keys that should be copied. If empty, no environment variables will be passed.
    public static func graph(at path: String? = nil, environmentKeys: Set<String> = []) throws -> Graph {
        // If a task is executed via `tuist`, it gets passed the binary path as a last argument.
        // Otherwise, fallback to go
        let tuistBinaryPath = ProcessInfo.processInfo.environment["TUIST_CONFIG_BINARY_PATH"] ?? "tuist"
        return try withTemporaryDirectory { temporaryDirectory -> Graph in
            let graphPath = temporaryDirectory.appending(component: "graph.json")
            var arguments = [
                tuistBinaryPath,
                "graph",
                "--format", "json",
                "--output-path", graphPath.parentDirectory.pathString,
            ]
            if let path = path {
                arguments += ["--path", path]
            }
            let forceConfigCacheDirectory = "TUIST_CONFIG_FORCE_CONFIG_CACHE_DIRECTORY"
            var environment: [String: String] = [:]
            for environmentKey in environmentKeys + [forceConfigCacheDirectory] {
                if let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty {
                    environment[environmentKey] = value
                }
            }
            try run(
                arguments,
                environment: environment
            )
            let graphData = try Data(contentsOf: graphPath.asURL)
            return try JSONDecoder().decode(Graph.self, from: graphData)
        }
    }

    private static func run(
        _ arguments: [String],
        environment: [String: String]
    ) throws {
        let process = Process(
            arguments: arguments,
            environment: environment,
            outputRedirection: .none,
            startNewProcessGroup: false
        )

        try process.launch()
        let result = try process.waitUntilExit()

        try result.throwIfErrored()
    }
}

extension ProcessResult {
    /// Throws a TuistError if the result is unsuccessful.
    ///
    /// - Throws: A TuistError.
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
