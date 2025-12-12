@_exported import ArgumentParser
import Foundation
import Noora
import OpenAPIRuntime
import Path
import TuistCore
import TuistHTTP
import TuistLoader
import TuistServer
import TuistSupport

public struct TuistCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tuist",
            abstract: "Build better apps faster.",
            subcommands: [],
            groupedSubcommands: [
                CommandGroup(
                    name: "Get started",
                    subcommands: [
                        InitCommand.self,
                    ]
                ),
                CommandGroup(
                    name: "Develop",
                    subcommands: [
                        HashCommand.self,
                        BuildCommand.self,
                        CacheCommand.self,
                        CacheStartCommand.self,
                        CleanCommand.self,
                        DumpCommand.self,
                        EditCommand.self,
                        GenerateCommand.self,
                        GraphCommand.self,
                        InstallCommand.self,
                        MigrationCommand.self,
                        PluginCommand.self,
                        RegistryCommand.self,
                        RunCommand.self,
                        ScaffoldCommand.self,
                        SetupCommand.self,
                        TestCommand.self,
                        InspectCommand.self,
                        XcodeBuildCommand.self,
                    ]
                ),
                CommandGroup(
                    name: "Share",
                    subcommands: [
                        ShareCommand.self,
                    ]
                ),
                CommandGroup(
                    name: "AI",
                    subcommands: [
                        MCPCommand.self,
                    ]
                ),
                CommandGroup(
                    name: "Account",
                    subcommands: [
                        AccountCommand.self,
                        ProjectCommand.self,
                        BundleCommand.self,
                        OrganizationCommand.self,
                        AuthCommand.self,
                    ]
                ),
                CommandGroup(
                    name: "Other",
                    subcommands: [
                        VersionCommand.self,
                        AnalyticsUploadCommand.self,
                    ]
                ),
            ]
        )
    }

    public static func main(
        logFilePath: AbsolutePath,
        _ arguments: [String]? = nil,
        parseAsRoot: ((_ arguments: [String]?) throws -> ParsableCommand) = Self.parseAsRoot
    ) async throws {
        let path: AbsolutePath
        if let argumentIndex = CommandLine.arguments.firstIndex(of: "--path") {
            path = try AbsolutePath(
                validating: CommandLine.arguments[argumentIndex + 1], relativeTo: .current
            )
        } else {
            path = .current
        }

        try await CacheDirectoriesProvider.bootstrap()

        let executeCommand: () async throws -> Void
        let processedArguments = Array(processArguments(arguments)?.dropFirst() ?? [])
        var parsingError: Error?
        var logFilePathDisplayStrategy: LogFilePathDisplayStrategy = .onError

        do {
            if processedArguments.first == ScaffoldCommand.configuration.commandName {
                try await ScaffoldCommand.preprocess(processedArguments)
            }
            let config = try await ConfigLoader().loadConfig(path: path)
            let serverURL = try ServerEnvironmentService().url(configServerURL: config.url)
            let command = try parseAsRoot(processedArguments)

            if command is RecentPathRememberableCommand {
                try await RecentPathsStore.current.remember(path: path)
            }

            executeCommand = {
                logFilePathDisplayStrategy =
                    (command as? LogConfigurableCommand)?
                        .logFilePathDisplayStrategy ?? logFilePathDisplayStrategy

                let trackableCommand = TrackableCommand(
                    command: command,
                    commandArguments: processedArguments
                )
                let shouldTrackAnalytics = processedArguments.prefix(2) != ["inspect", "build"]
                    && processedArguments.prefix(2) != ["auth", "refresh-token"]
                    && processedArguments.first != "analytics-upload"
                if let nooraReadyCommand = command as? NooraReadyCommand {
                    let jsonThroughNoora = nooraReadyCommand.jsonThroughNoora
                    try await withLoggerForNoora(logFilePath: logFilePath) {
                        try await Noora.$current.withValue(initNoora(jsonThroughNoora: jsonThroughNoora)) {
                            try await trackableCommand.run(
                                fullHandle: config.fullHandle,
                                serverURL: serverURL,
                                shouldTrackAnalytics: shouldTrackAnalytics
                            )
                        }
                    }
                } else {
                    try await trackableCommand.run(
                        fullHandle: config.fullHandle,
                        serverURL: serverURL,
                        shouldTrackAnalytics: shouldTrackAnalytics
                    )
                }
            }
        } catch {
            parsingError = error
            executeCommand = {
                try await executeTask(with: processedArguments)
            }
        }

        do {
            try await executeCommand()
            // We need to reinitialize Noora as by default, the logger is the legacy one until we migrate all commands to be
            // `NooraReadyCommand` and the subsequent Noora messages would be missing from the verbose logs.
            try await withLoggerForNoora(logFilePath: logFilePath) {
                Noora.$current.withValue(initNoora()) {
                    outputCompletion(
                        logFilePath: logFilePath,
                        shouldOutputLogFilePath: logFilePathDisplayStrategy == .always
                    )
                }
            }
        } catch {
            try await withLoggerForNoora(logFilePath: logFilePath) {
                Noora.$current.withValue(initNoora()) {
                    onError(
                        parsingError ?? error, isParsingError: parsingError != nil, logFilePath: logFilePath
                    )
                }
            }
        }
    }

    private static func onError(_ error: Error, isParsingError: Bool, logFilePath: AbsolutePath) {
        var errorAlertMessage: TerminalText?
        var errorAlertNextSteps: [TerminalText] = [
            "If the error is actionable, address it",
            "If the error is not actionable, let's discuss it in the \(.link(title: "Troubleshooting & how to", href: "https://community.tuist.dev/c/troubleshooting-how-to/6"))",
            "If you are very certain it's a bug, \(.link(title: "file an issue", href: "https://github.com/tuist/tuist"))",
        ]
        let exitCode = exitCode(for: error).rawValue

        if error.localizedDescription.contains("ArgumentParser") {
            // Let argument parser handle the error
            exit(withError: error)
        } else if let clientError = error as? ClientError,
                  let underlyingAuthError = clientError.underlyingError
                  as? ClientAuthenticationError
        {
            errorAlertMessage = "\(underlyingAuthError.errorDescription ?? "Unknown error")"
        } else if let fatalError = error as? FatalError {
            let isSilent = fatalError.type == .abortSilent || fatalError.type == .bugSilent
            if !fatalError.description.isEmpty, !isSilent {
                errorAlertMessage = "\(fatalError.description)"
            } else if fatalError.type == .bugSilent {
                errorAlertMessage = """
                An unexpected error happened and we believe it's a bug
                """
                errorAlertNextSteps = [
                    "\(.link(title: "File an issue", href: "https://github.com/tuist/tuist")) including reproducible steps and logs.",
                ]
            }
        } else if isParsingError, self.exitCode(for: error).rawValue == 0 {
            // Let argument parser handle the error
            exit(withError: error)
        } else if let localizedError = error as? LocalizedError {
            errorAlertMessage =
                "\(localizedError.errorDescription ?? localizedError.localizedDescription)"
        } else {
            errorAlertMessage = "\((error as CustomStringConvertible).description)"
        }

        outputCompletion(
            logFilePath: logFilePath,
            shouldOutputLogFilePath: true,
            errorAlertMessage: errorAlertMessage,
            errorAlertNextSteps: errorAlertNextSteps
        )
        _exit(exitCode)
    }

    private static func outputCompletion(
        logFilePath: AbsolutePath,
        shouldOutputLogFilePath: Bool,
        errorAlertMessage: TerminalText? = nil,
        errorAlertNextSteps: [TerminalText]? = nil
    ) {
        if Environment.current.isJSONOutput { return }

        let errorAlert: ErrorAlert? =
            if let errorAlertMessage {
                .alert(errorAlertMessage, takeaways: errorAlertNextSteps ?? [])
            } else {
                nil
            }
        let successAlerts = AlertController.current.success()
        let warningAlerts = AlertController.current.warnings()
        let takeaways = AlertController.current.takeaways()

        if !warningAlerts.isEmpty {
            print("\n")
            Noora.current.warning(warningAlerts)
        }
        let logsNextStep: TerminalText = "Check out the logs at \(logFilePath.pathString)"

        if let errorAlert {
            print("\n")
            var errorAlertNextSteps = errorAlert.takeaways
            if shouldOutputLogFilePath {
                errorAlertNextSteps.append(logsNextStep)
            }
            Noora.current.error(.alert(errorAlert.message, takeaways: errorAlertNextSteps))
        } else if let successAlert = successAlerts.last {
            var successAlertNextSteps = successAlert.takeaways
            successAlertNextSteps.append(contentsOf: takeaways)
            if shouldOutputLogFilePath {
                successAlertNextSteps.append(logsNextStep)
            }
            print("\n")
            Noora.current.success(.alert(successAlert.message, takeaways: successAlertNextSteps))
        }
    }

    private static func executeTask(with processedArguments: [String]) async throws {
        try await TuistService().run(
            arguments: processedArguments,
            tuistBinaryPath: processArguments()!.first!
        )
    }

    // MARK: - Helpers

    static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(Environment.current.arguments)
        return arguments.filter { $0 != "--verbose" && $0 != "--quiet" }
    }
}
