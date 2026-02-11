@_exported import ArgumentParser
import Foundation
import Noora
import OpenAPIRuntime
import Path
import TuistAccountCommand
import TuistAlert
import TuistAuthCommand
import TuistBuildCommand
import TuistBundleCommand
import TuistCacheCommand
import TuistConfigLoader
import TuistEnvironment
import TuistGenerateCommand
import TuistInitCommand
import TuistLogging
import TuistNooraExtension
import TuistOrganizationCommand
import TuistProjectCommand
import TuistRegistryCommand
import TuistTestCommand
import TuistVersionCommand

#if os(macOS)
    import TuistCore
    import TuistHTTP
    import TuistKit
    import TuistLoader
    import TuistServer
    import TuistSupport
#endif

public struct TuistCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tuist",
            abstract: "Build better apps faster.",
            groupedSubcommands: groupedSubcommands
        )
    }

    private static var groupedSubcommands: [CommandGroup] {
        var groups: [CommandGroup] = []

        #if os(macOS)
            groups += [
                CommandGroup(
                    name: "Get started",
                    subcommands: [InitCommand.self]
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
                    subcommands: [ShareCommand.self]
                ),
                CommandGroup(
                    name: "AI",
                    subcommands: [MCPCommand.self]
                ),
            ]
        #endif

        groups.append(CommandGroup(
            name: "Account",
            subcommands: accountSubcommands
        ))

        #if !os(macOS)
            groups.append(CommandGroup(
                name: "Get started",
                subcommands: [InitCommand.self]
            ))
            groups.append(CommandGroup(
                name: "Develop",
                subcommands: [
                    BuildCommand.self,
                    CacheCommand.self,
                    GenerateCommand.self,
                    TestCommand.self,
                ]
            ))
        #endif

        groups.append(CommandGroup(
            name: "Other",
            subcommands: otherSubcommands
        ))

        return groups
    }

    private static var accountSubcommands: [ParsableCommand.Type] {
        [
            AccountCommand.self,
            ProjectCommand.self,
            BundleCommand.self,
            OrganizationCommand.self,
            AuthCommand.self,
        ]
    }

    private static var otherSubcommands: [ParsableCommand.Type] {
        #if os(macOS)
            [VersionCommand.self, AnalyticsUploadCommand.self]
        #else
            [VersionCommand.self]
        #endif
    }

    public static func main(
        logFilePath: AbsolutePath,
        _ arguments: [String]? = nil,
        parseAsRoot: ((_ arguments: [String]?) throws -> ParsableCommand) = Self.parseAsRoot
    ) async throws {
        let processedArguments = Array(processArguments(arguments)?.dropFirst() ?? [])

        #if os(macOS)
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
        #else
            try await withLoggerForNoora(logFilePath: logFilePath) {
                try await Noora.$current.withValue(initNoora()) {
                    do {
                        var command = try parseAsRoot(processedArguments)
                        if var asyncCommand = command as? AsyncParsableCommand {
                            try await asyncCommand.run()
                        } else {
                            try command.run()
                        }
                        outputCompletion(
                            logFilePath: logFilePath,
                            shouldOutputLogFilePath: false
                        )
                    } catch {
                        onError(error, isParsingError: false, logFilePath: logFilePath)
                    }
                }
            }
        #endif
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
            exit(withError: error)
        }

        var errorHandled = false

        #if os(macOS)
            if let clientError = error as? ClientError,
               let underlyingAuthError = clientError.underlyingError as? ClientAuthenticationError
            {
                errorAlertMessage = "\(underlyingAuthError.errorDescription ?? "Unknown error")"
                errorHandled = true
            }
        #endif

        if !errorHandled, let fatalError = error as? FatalError {
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
            errorHandled = true
        }

        if !errorHandled, isParsingError, self.exitCode(for: error).rawValue == 0 {
            exit(withError: error)
        } else if !errorHandled, let localizedError = error as? LocalizedError {
            errorAlertMessage =
                "\(localizedError.errorDescription ?? localizedError.localizedDescription)"
        } else if !errorHandled {
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

    #if os(macOS)
        private static func executeTask(with processedArguments: [String]) async throws {
            try await TuistService().run(
                arguments: processedArguments,
                tuistBinaryPath: processArguments()!.first!
            )
        }
    #endif

    public static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(Environment.current.arguments)
        return arguments.filter { $0 != "--verbose" && $0 != "--quiet" }
    }
}
