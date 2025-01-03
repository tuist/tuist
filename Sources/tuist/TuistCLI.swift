import Foundation
import Path
import ServiceContextModule
import TSCBasic
import TuistKit
import TuistLoader
import TuistSupport

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        if CommandLine.arguments.contains("--quiet") && CommandLine.arguments.contains("--verbose") {
            throw TuistCLIError.exclusiveOptionError("quiet", "verbose")
        }

        if CommandLine.arguments.contains("--quiet") && CommandLine.arguments.contains("--json") {
            throw TuistCLIError.exclusiveOptionError("quiet", "json")
        }

        if CommandLine.arguments.contains("--verbose") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true")
        }

        if CommandLine.arguments.contains("--quiet") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.quiet, value: "true")
        }

        let machineReadableCommands = [DumpCommand.self]

        // swiftformat:disable all
        let isCommandMachineReadable = CommandLine.arguments.count > 1 && machineReadableCommands.map { $0._commandName }.contains(CommandLine.arguments[1])
        // swiftformat:enable all
        let loggingConfig = if isCommandMachineReadable || CommandLine.arguments.contains("--json") {
            LoggingConfig(
                loggerType: .json,
                verbose: ProcessEnv.vars[Constants.EnvironmentVariables.verbose] != nil
            )
        } else {
            LoggingConfig.default
        }
        let loggerHandler = Logger.defaultLoggerHandler(config: loggingConfig)

        /// This is the old initialization method and will eventually go away.
        LoggingSystem.bootstrap(loggerHandler)

        var context = ServiceContext.topLevel
        context.logger = Logger(label: "dev.tuist.cli", factory: loggerHandler)

        try await ServiceContext.withValue(context) {
            try await TuistCommand.main()
        }
    }
}

private enum TuistCLIError: FatalError {
    case exclusiveOptionError(String, String)

    var description: String {
        switch self {
        case let .exclusiveOptionError(option1, option2):
            "Cannot use --\(option1) and --\(option2) at the same time."
        }
    }

    var type: ErrorType {
        switch self {
        case .exclusiveOptionError:
            .abort
        }
    }
}
