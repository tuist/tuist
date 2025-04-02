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

extension ServiceContext {
    public static func tuist(_ action: (Path.AbsolutePath) async throws -> Void) async throws {
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

        try await LogsController().setup(stateDirectory: Environment.shared.stateDirectory) { loggerHandler, logFilePath in
            /// This is the old initialization method and will eventually go away.
            LoggingSystem.bootstrap(loggerHandler)

            var context = ServiceContext.topLevel
            context.logger = Logger(label: "dev.tuist.cli", factory: loggerHandler)
            context.ui = Noora()
            context.alerts = AlertController()
            context.recentPaths = RecentPathsStore(storageDirectory: Environment.shared.stateDirectory)

            try await ServiceContext.withValue(context) {
                try await action(logFilePath)
            }
        }
    }
}
