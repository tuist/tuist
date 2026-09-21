@_exported import ArgumentParser
import Foundation
import Noora
import OpenAPIRuntime
import Path
import TuistAccountCommand
import TuistAlert
import TuistAuthCommand
import TuistBazelCommand
import TuistBuildCommand
import TuistBundleCommand
import TuistCacheCommand
import TuistConfigLoader
import TuistEnvironment
import TuistGenerateCommand
import TuistInitCommand
import TuistInspectCommand
import TuistLogging
import TuistNooraExtension
import TuistOrganizationCommand
import TuistProjectCommand
import TuistRegistryCommand
import TuistRunCommand
import TuistRunnerCommand
import TuistShareCommand
import TuistSupport
import TuistTestCommand
import TuistVersionCommand

#if os(macOS)
    import TuistCore
    import TuistHAR
    import TuistHTTP
    import TuistKit
    import TuistLoader
    import TuistServer
#endif

/// Thrown instead of exiting the process when Tuist runs embedded in another program.
public struct EmbeddedExit: Error {
    public let code: Int32
}

public struct TuistCommand: AsyncParsableCommand {
    public init() {}

    /// When true, the CLI reports its exit code by throwing `EmbeddedExit` instead of
    /// terminating the process, so a host that links Tuist decides when to exit.
    @TaskLocal public static var isEmbedded = false

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
                        BazelCommand.self,
                        BuildCommand.self,
                        CacheCommand.self,
                        CacheProxyCommand.self,
                        CacheStartCommand.self,
                        SampleHostMetricsCommand.self,
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
                        RunnerCommand.self,
                        ScaffoldCommand.self,
                        SetupCommand.self,
                        TeardownCommand.self,
                        TestCommand.self,
                        InspectCommand.self,
                        XcodeBuildCommand.self,
                    ]
                ),
                CommandGroup(
                    name: "Share",
                    subcommands: [ShareCommand.self]
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
                    BazelCommand.self,
                    BuildCommand.self,
                    CacheCommand.self,
                    GenerateCommand.self,
                    RunCommand.self,
                    RunnerCommand.self,
                    TestCommand.self,
                    InspectCommand.self,
                ]
            ))
            groups.append(CommandGroup(
                name: "Share",
                subcommands: [ShareCommand.self]
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

    // swiftlint:disable:next function_body_length
    public static func main(
        logFilePath: AbsolutePath,
        sessionDirectory: AbsolutePath,
        networkFilePath: AbsolutePath,
        _ arguments: [String]? = nil,
        parseAsRoot: ((_ arguments: [String]?) throws -> ParsableCommand) = Self.parseAsRoot
    ) async throws {
        let processedArguments = Array(processArguments(arguments)?.dropFirst() ?? [])

        #if os(macOS)
            let path = try await CommandArguments.path(in: processedArguments)

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
                let shouldRecordHAR = (command as? HARRecordingCommand)?.shouldRecordHAR ?? true

                executeCommand = {
                    logFilePathDisplayStrategy =
                        (command as? LogConfigurableCommand)?
                            .logFilePathDisplayStrategy ?? logFilePathDisplayStrategy

                    let trackableCommand = TrackableCommand(
                        command: command,
                        commandArguments: processedArguments,
                        sessionDirectory: sessionDirectory
                    )
                    let shouldTrackAnalytics = processedArguments.prefix(2) != ["inspect", "build"]
                        && processedArguments.prefix(2) != ["auth", "refresh-token"]
                        && processedArguments.prefix(2) != ["bazel", "credential-helper"]
                        && processedArguments.first != "analytics-upload"
                    let optionalAuthentication = config.project.optionalAuthentication
                    let runTrackableCommand = {
                        try await withHARRecorder(
                            networkFilePath: networkFilePath,
                            shouldRecordHAR: shouldRecordHAR
                        ) {
                            try await trackableCommand.run(
                                fullHandle: config.fullHandle,
                                serverURL: serverURL,
                                shouldTrackAnalytics: shouldTrackAnalytics,
                                optionalAuthentication: optionalAuthentication
                            )
                        }
                    }
                    if let nooraReadyCommand = command as? NooraReadyCommand {
                        let jsonThroughNoora = nooraReadyCommand.jsonThroughNoora
                        try await withLoggerForNoora(logFilePath: logFilePath) {
                            try await Noora.$current.withValue(initNoora(jsonThroughNoora: jsonThroughNoora)) {
                                try await runTrackableCommand()
                            }
                        }
                    } else {
                        try await runTrackableCommand()
                    }
                }
            } catch {
                parsingError = error
                executeCommand = {
                    try await withHARRecorder(
                        networkFilePath: networkFilePath,
                        shouldRecordHAR: true
                    ) {
                        try await executeTask(with: processedArguments)
                    }
                }
            }

            do {
                try await executeCommand()
                if !MachineReadableOutput.isEnabled(arguments: Environment.current.arguments) {
                    try await withLoggerForNoora(logFilePath: logFilePath) {
                        Noora.$current.withValue(initNoora()) {
                            outputCompletion(
                                logFilePath: logFilePath,
                                shouldOutputLogFilePath: logFilePathDisplayStrategy == .always
                            )
                        }
                    }
                }
            } catch {
                try await withLoggerForNoora(logFilePath: logFilePath) {
                    try await Noora.$current.withValue(initNoora()) {
                        try await onError(
                            parsingError ?? error, isParsingError: parsingError != nil, logFilePath: logFilePath
                        )
                    }
                }
            }
        #else
            try await withLoggerForNoora(logFilePath: logFilePath) {
                do {
                    let command = try parseAsRoot(processedArguments)
                    let jsonThroughNoora = (command as? NooraReadyCommand)?.jsonThroughNoora ?? false
                    try await Noora.$current.withValue(initNoora(jsonThroughNoora: jsonThroughNoora)) {
                        if var asyncCommand = command as? AsyncParsableCommand {
                            try await asyncCommand.run()
                        } else {
                            var mutableCommand = command
                            try mutableCommand.run()
                        }
                        outputCompletion(
                            logFilePath: logFilePath,
                            shouldOutputLogFilePath: false
                        )
                    }
                } catch {
                    try await onError(error, isParsingError: false, logFilePath: logFilePath)
                }
            }
        #endif
    }

    private static func onError(_ error: Error, isParsingError: Bool, logFilePath: AbsolutePath) async throws {
        var errorAlertMessage: TerminalText?
        var errorAlertNextSteps: [TerminalText] = [
            "If the error is actionable, address it",
            "If the error is not actionable, let's discuss it in the \(.link(title: "Troubleshooting & how to", href: "https://community.tuist.dev/c/troubleshooting-how-to/6"))",
            "If you are very certain it's a bug, \(.link(title: "file an issue", href: "https://github.com/tuist/tuist"))",
        ]
        let exitCode = exitCode(for: error).rawValue

        if error.localizedDescription.contains("ArgumentParser") {
            await finishHARRecordingBeforeExit()
            try terminate(withError: error)
        }

        if let remoteExit = error as? RunnerShellRemoteExitError {
            await finishHARRecordingBeforeExit()
            try terminate(remoteExit.status)
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
            await finishHARRecordingBeforeExit()
            try terminate(withError: error)
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
        await finishHARRecordingBeforeExit()
        try terminate(exitCode)
    }

    /// Ends the run with `code`: exits the process, or throws `EmbeddedExit` when embedded.
    private static func terminate(_ code: Int32) throws -> Never {
        if isEmbedded {
            throw EmbeddedExit(code: code)
        }
        _exit(code)
    }

    /// Prints the parser's message for `error` and ends the run with its exit code, the way
    /// `exit(withError:)` does, but without exiting the process when embedded.
    private static func terminate(withError error: Error) throws -> Never {
        guard isEmbedded else { exit(withError: error) }
        let code = exitCode(for: error)
        let message = fullMessage(for: error)
        if !message.isEmpty {
            if code == .success {
                print(message)
            } else {
                FileHandle.standardError.write(Data((message + "\n").utf8))
            }
        }
        throw EmbeddedExit(code: code.rawValue)
    }

    private static func finishHARRecordingBeforeExit() async {
        #if os(macOS)
            await HARRecorder.finishCurrent()
        #endif
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
            Noora.current.warning(warningAlerts)
        }
        let logsNextStep: TerminalText = "Check out the logs at \(logFilePath.pathString)"

        if let errorAlert {
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

        private static func withHARRecorder(
            networkFilePath: AbsolutePath,
            shouldRecordHAR: Bool,
            _ action: () async throws -> Void
        ) async throws {
            if shouldRecordHAR, HARRecorder.current != nil {
                try await action()
                return
            }

            let harRecorder: HARRecorder? =
                shouldRecordHAR ? HARRecorder(filePath: networkFilePath) : nil
            try await HARRecorder.withCurrent(harRecorder) {
                try await action()
            }
        }
    #endif

    public static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(Environment.current.arguments)
        return arguments.filter { $0 != "--verbose" && $0 != "--quiet" }
    }
}
