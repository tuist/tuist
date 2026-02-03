import FileSystem
import Foundation
import Path
import TuistEnvironment

private actor AsyncLock {
    func withLock<T>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        try await operation()
    }
}

public struct LogsController {
    private static let logsDirectoryLock = AsyncLock()
    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func setup(
        stateDirectory: AbsolutePath,
        logFilePath: AbsolutePath! = nil,
        machineReadableCommandNames: [String] = []
    ) async throws -> (@Sendable (String) -> any LogHandler, AbsolutePath) {
        var logFilePath = logFilePath
        if logFilePath == nil {
            logFilePath = try await touchLogFile(stateDirectory: stateDirectory)
        }

        let isCommandMachineReadable =
            CommandLine.arguments.count > 1
            && machineReadableCommandNames.contains(CommandLine.arguments[1])

        let loggingConfig =
            if isCommandMachineReadable || CommandLine.arguments.contains("--json") {
                LoggingConfig(
                    loggerType: .json,
                    verbose: Environment.current.isVerbose
                )
            } else {
                LoggingConfig.default()
            }

        try await clean(logsDirectory: logFilePath!.parentDirectory)

        let loggerHandler = try Logger.defaultLoggerHandler(
            config: loggingConfig, logFilePath: logFilePath!
        )

        return (loggerHandler, logFilePath!)
    }

    private func clean(logsDirectory: AbsolutePath) async throws {
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!

        for logPath in try await fileSystem.glob(directory: logsDirectory, include: ["*"]).collect() {
            if let creationDate = try FileManager.default.attributesOfItem(atPath: logPath.pathString)[.creationDate] as? Date,
               creationDate < fiveDaysAgo
            {
                try await fileSystem.remove(logPath)
            }
        }
    }

    private func touchLogFile(stateDirectory: AbsolutePath) async throws -> Path.AbsolutePath {
        let fileSystem = FileSystem()
        let logFilePath = stateDirectory.appending(components: [
            "logs", "\(UUID().uuidString).log",
        ])
        try await Self.logsDirectoryLock.withLock {
            if try await !fileSystem.exists(logFilePath.parentDirectory, isDirectory: true) {
                do {
                    try await fileSystem.makeDirectory(at: logFilePath.parentDirectory)
                } catch let error as NSError where error.domain == "NIOFileSystemErrorDomain"
                    && error.userInfo["code"] as? String == "fileAlreadyExists"
                {
                    // Directory was created by another process between our check and creation attempt
                } catch {
                    // Check if the directory now exists (race condition with another process)
                    if try await !fileSystem.exists(logFilePath.parentDirectory, isDirectory: true) {
                        throw error
                    }
                }
            }
        }
        try await fileSystem.touch(logFilePath)
        return logFilePath
    }
}
