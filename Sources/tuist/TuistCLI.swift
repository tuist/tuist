import FileSystem
import Foundation
import Noora
import Path
import ServiceContextModule
import TSCBasic
import TuistKit
import TuistSupport

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--verbose") {
            throw TuistCLIError.exclusiveOptionError("quiet", "verbose")
        }

        if CommandLine.arguments.contains("--quiet"), CommandLine.arguments.contains("--json") {
            throw TuistCLIError.exclusiveOptionError("quiet", "json")
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
            context.ui = CLIUI()
            context.alerts = AlertController()

            try await ServiceContext.withValue(context) {
                try await TuistCommand.main(logFilePath: logFilePath)
            }
        }
    }
}

#error("TODO: is a simple proxy on top of Noora ok?")
#error("TODO: where to place this?")
struct CLIUI: Noorable {
    // MARK: - Properties

    let noora = Noora()
    let isQuiet: Bool = ProcessInfo.processInfo.environment[Constants.EnvironmentVariables.quiet] != nil

    func message(_ text: TerminalText) {
        #error(
            "TODO: better way to format? - there is no direct method on Noora to format like mentioned here: https://noora.tuist.dev/text-styling"
        )
        print(text.formatted(theme: .default, terminal: Terminal()))
    }

    // MARK: - Noorable

    func success(_ alert: SuccessAlert) {
        if !isQuiet {
            noora.success(alert)
        }
    }

    func error(_ alert: ErrorAlert) {
        #error("TODO: Should UI errors be printed even if quiet?")
        if !isQuiet {
            noora.error(alert)
        }
    }

    func warning(_ alerts: WarningAlert...) {
        if !isQuiet {
            noora.warning(alerts)
        }
    }

    func warning(_ alerts: [WarningAlert]) {
        if !isQuiet {
            noora.warning(alerts)
        }
    }

    func progressStep(
        message: String,
        successMessage: String?,
        errorMessage: String?,
        showSpinner: Bool,
        task: @escaping ((String) -> Void) async throws -> Void
    ) async throws {
        if !isQuiet {
            try await noora.progressStep(
                message: message,
                successMessage: successMessage,
                errorMessage: errorMessage,
                showSpinner: showSpinner,
                task: task
            )
        }
    }

    func collapsibleStep(
        title: TerminalText,
        successMessage: TerminalText?,
        errorMessage: TerminalText?,
        visibleLines: UInt,
        task: @escaping (@escaping (TerminalText) -> Void) async throws -> Void
    ) async throws {
        if !isQuiet {
            try await noora.collapsibleStep(
                title: title,
                successMessage: successMessage,
                errorMessage: errorMessage,
                visibleLines: visibleLines,
                task: task
            )
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
