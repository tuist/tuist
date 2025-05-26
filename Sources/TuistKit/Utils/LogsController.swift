import FileSystem
import Foundation
import Path
import TuistSupport

public struct LogsController {
    private let fileSystem: FileSystem

    public init(fileSystem: FileSystem = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func setup(
        stateDirectory: AbsolutePath,
        logFilePath: AbsolutePath! = nil
    ) async throws -> (@Sendable (String) -> any LogHandler, AbsolutePath) {
        var logFilePath = logFilePath
        if logFilePath == nil {
            logFilePath = try await touchLogFile(stateDirectory: stateDirectory)
        }
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
        if !(try await fileSystem.exists(logFilePath.parentDirectory)) {
            try await fileSystem.makeDirectory(at: logFilePath.parentDirectory)
        }
        try await fileSystem.touch(logFilePath)
        return logFilePath
    }
}
