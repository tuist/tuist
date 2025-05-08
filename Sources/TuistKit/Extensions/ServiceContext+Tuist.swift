import Foundation
import Noora
import Path
import ServiceContextModule
import TSCBasic
import TuistSupport

private enum TuistServiceContextError: LocalizedError {
    case exclusiveOptionError(String, String)

    var errorDescription: String? {
        switch self {
        case let .exclusiveOptionError(option1, option2):
            "Cannot use --\(option1) and --\(option2) at the same time."
        }
    }
}

struct IgnoreOutputPipeline: StandardPipelining {
    func write(content _: String) {}
}

extension ServiceContext {
    public static func tuist(_ action: (Path.AbsolutePath) async throws -> Void) async throws {
        try setupEnv()

        var context = ServiceContext.topLevel

        let (logger, logFilePath) = try await setupLogger()
        context.logger = logger
        context.ui = setupNoora()
        context.alerts = AlertController()
        context.recentPaths = RecentPathsStore(storageDirectory: Environment.shared.stateDirectory)

        try await ServiceContext.withValue(context) {
            try await action(logFilePath)
        }
    }

    private static func setupEnv() throws {
        if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--verbose") {
            throw TuistServiceContextError.exclusiveOptionError("quiet", "verbose")
        }

        if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--json") {
            throw TuistServiceContextError.exclusiveOptionError("quiet", "json")
        }

        if CommandLine.arguments.contains("--verbose") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true")
        }

        if CommandLine.arguments.contains("--quiet") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.quiet, value: "true")
        }

        if CommandLine.arguments.contains("--warnings-as-errors") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.warningsAsErrors, value: "true")
        }
    }

    func withLoggerForNoora(logFilePath: Path.AbsolutePath, _ action: () async throws -> Void) async throws {
        var context = self
        let loggerHandler = try Logger.loggerHandlerForNoora(logFilePath: logFilePath)
        context.logger = Logger(label: "dev.tuist.cli", factory: loggerHandler)
        try await ServiceContext.withValue(context) {
            try await action()
        }
    }

    static func setupLogger() async throws -> (Logger, Path.AbsolutePath) {
        let (loggerHandler, logFilePath) = try await LogsController().setup(
            stateDirectory: Environment.shared.stateDirectory
        )
        /// This is the old initialization method and will eventually go away.
        LoggingSystem.bootstrap(loggerHandler)
        return (Logger(label: "dev.tuist.cli", factory: loggerHandler), logFilePath)
    }

    private static func setupNoora() -> Noora {
        if CommandLine.arguments.contains("--json") || CommandLine.arguments.contains("--quiet") {
            Noora(
                standardPipelines: StandardPipelines(
                    output: IgnoreOutputPipeline()
                )
            )
        } else {
            Noora()
        }
    }
}
