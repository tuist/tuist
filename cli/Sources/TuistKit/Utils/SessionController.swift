import FileSystem
import Foundation
import Path
import TuistEnvironment
import TuistLogging
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

        let loggerHandler = try Logger.defaultLoggerHandler(
            config: loggingConfig, logFilePath: sessionPaths.logFilePath
        )

        return (loggerHandler, sessionPaths)
    }

    /// Schedules best-effort cleanup of old session directories.
    public func scheduleMaintenance(stateDirectory: AbsolutePath) {
        Task.detached(priority: .background) { [fileSystem] in
            try? await Self.clean(fileSystem: fileSystem, stateDirectory: stateDirectory)
        }
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

    /// Cleans up old session directories based on age and count limits.
    /// - Parameters:
    ///   - stateDirectory: The base state directory.
    ///   - maxAge: Maximum age of sessions to keep (default: 5 days).
    ///   - maxSessions: Maximum number of sessions to keep (default: 50).
    static func clean(
        fileSystem: FileSystem,
        stateDirectory: AbsolutePath,
        maxAge: TimeInterval = 5 * 24 * 60 * 60,
        maxSessions: Int = 50
    ) async throws {
        let sessionsDirectory = stateDirectory.appending(component: "sessions")
        guard try await fileSystem.exists(sessionsDirectory) else { return }

        let cutoffDate = Date().addingTimeInterval(-maxAge)

        var sessionsWithDates: [(path: AbsolutePath, creationDate: Date)] = []

        for sessionPath in try await fileSystem.glob(directory: sessionsDirectory, include: ["*"]).collect() {
            guard let creationDate = try FileManager.default.attributesOfItem(
                atPath: sessionPath.pathString
            )[.creationDate] as? Date else { continue }

            if creationDate < cutoffDate {
                try await fileSystem.remove(sessionPath)
            } else {
                sessionsWithDates.append((path: sessionPath, creationDate: creationDate))
            }
        }

        if sessionsWithDates.count > maxSessions {
            sessionsWithDates.sort { $0.creationDate > $1.creationDate }
            let sessionsToRemove = sessionsWithDates.dropFirst(maxSessions)
            for session in sessionsToRemove {
                try await fileSystem.remove(session.path)
            }
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
