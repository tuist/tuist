import FileSystem
import Foundation
import Path
import TuistSupport

/// Manages CLI session directories containing logs and network recordings.
///
/// Session directories are stored at `$XDG_STATE_HOME/tuist/sessions/<UUID>/`
/// and contain:
/// - `logs.txt`: The text log file for the session
/// - `network.har`: HTTP Archive file containing all network requests/responses
public struct SessionController {
    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Sets up a new CLI session with logging and network recording.
    /// - Parameter stateDirectory: The base state directory (typically `$XDG_STATE_HOME/tuist`).
    /// - Returns: A tuple containing the logger handler factory and the session paths.
    public func setup(
        stateDirectory: AbsolutePath
    ) async throws -> (@Sendable (String) -> any LogHandler, SessionPaths) {
        let sessionPaths = try await createSessionDirectory(stateDirectory: stateDirectory)

        let machineReadableCommands = [DumpCommand.self]
        // swiftformat:disable all
        let isCommandMachineReadable =
            CommandLine.arguments.count > 1
            && machineReadableCommands.map { $0._commandName }.contains(CommandLine.arguments[1])
        // swiftformat:enable all
        let loggingConfig =
            if isCommandMachineReadable || CommandLine.arguments.contains("--json") {
                LoggingConfig(
                    loggerType: .json,
                    verbose: Environment.current.isVerbose
                )
            } else {
                LoggingConfig.default()
            }

        try await clean(stateDirectory: stateDirectory)
        try await migrateOldLogs(stateDirectory: stateDirectory)

        let loggerHandler = try Logger.defaultLoggerHandler(
            config: loggingConfig, logFilePath: sessionPaths.logFilePath
        )

        return (loggerHandler, sessionPaths)
    }

    /// Creates a new session directory and returns the paths for logs and network recording.
    /// - Parameters:
    ///   - stateDirectory: The base state directory (typically `$XDG_STATE_HOME/tuist`).
    ///   - sessionId: Optional session ID. If nil, a new UUID will be generated.
    /// - Returns: The session paths.
    private func createSessionDirectory(
        stateDirectory: AbsolutePath,
        sessionId: String? = nil
    ) async throws -> SessionPaths {
        let id = sessionId ?? UUID().uuidString
        let sessionDirectory = stateDirectory.appending(components: ["sessions", id])

        if !(try await fileSystem.exists(sessionDirectory)) {
            try await fileSystem.makeDirectory(at: sessionDirectory)
        }

        let logFilePath = sessionDirectory.appending(component: "logs.txt")
        let networkFilePath = sessionDirectory.appending(component: "network.har")

        try await fileSystem.touch(logFilePath)

        return SessionPaths(
            sessionId: id,
            sessionDirectory: sessionDirectory,
            logFilePath: logFilePath,
            networkFilePath: networkFilePath
        )
    }

    /// Cleans up old session directories.
    /// - Parameters:
    ///   - stateDirectory: The base state directory.
    ///   - maxAge: Maximum age of sessions to keep (default: 5 days).
    private func clean(stateDirectory: AbsolutePath, maxAge: TimeInterval = 5 * 24 * 60 * 60) async throws {
        let sessionsDirectory = stateDirectory.appending(component: "sessions")
        guard try await fileSystem.exists(sessionsDirectory) else { return }

        let cutoffDate = Date().addingTimeInterval(-maxAge)

        for sessionPath in try await fileSystem.glob(directory: sessionsDirectory, include: ["*"]).collect() {
            if let creationDate = try FileManager.default.attributesOfItem(
                atPath: sessionPath.pathString
            )[.creationDate] as? Date,
                creationDate < cutoffDate
            {
                try await fileSystem.remove(sessionPath)
            }
        }
    }

    /// Migrates old logs directory to the new sessions structure.
    /// This ensures backward compatibility during the transition period.
    /// - Parameter stateDirectory: The base state directory.
    private func migrateOldLogs(stateDirectory: AbsolutePath) async throws {
        let oldLogsDirectory = stateDirectory.appending(component: "logs")
        guard try await fileSystem.exists(oldLogsDirectory) else { return }

        let cutoffDate = Date().addingTimeInterval(-5 * 24 * 60 * 60)

        for logPath in try await fileSystem.glob(directory: oldLogsDirectory, include: ["*.log"]).collect() {
            if let creationDate = try FileManager.default.attributesOfItem(
                atPath: logPath.pathString
            )[.creationDate] as? Date,
                creationDate < cutoffDate
            {
                try await fileSystem.remove(logPath)
            }
        }

        let remainingFiles = try await fileSystem.glob(directory: oldLogsDirectory, include: ["*"]).collect()
        if remainingFiles.isEmpty {
            try await fileSystem.remove(oldLogsDirectory)
        }
    }
}

/// Paths for a CLI session.
public struct SessionPaths: Sendable {
    /// The unique session identifier.
    public let sessionId: String

    /// The session directory path.
    public let sessionDirectory: AbsolutePath

    /// The path to the log file.
    public let logFilePath: AbsolutePath

    /// The path to the HAR file for network recordings.
    public let networkFilePath: AbsolutePath

    public init(
        sessionId: String,
        sessionDirectory: AbsolutePath,
        logFilePath: AbsolutePath,
        networkFilePath: AbsolutePath
    ) {
        self.sessionId = sessionId
        self.sessionDirectory = sessionDirectory
        self.logFilePath = logFilePath
        self.networkFilePath = networkFilePath
    }
}
