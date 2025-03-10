@_exported import ArgumentParser
import Foundation
import Noora
import OpenAPIRuntime
import Path
import ServiceContextModule
import TuistAnalytics
import TuistCore
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
                        BuildCommand.self,
                        CacheCommand.self,
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
                    name: "Account",
                    subcommands: [
                        AccountCommand.self,
                        ProjectCommand.self,
                        OrganizationCommand.self,
                        AuthCommand.self,
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
            path = try AbsolutePath(validating: CommandLine.arguments[argumentIndex + 1], relativeTo: .current)
        } else {
            path = .current
        }

        let config = try await ConfigLoader().loadConfig(path: path)
        let url = try ServerURLService().url(configServerURL: config.url)
        let backend: TuistAnalyticsServerBackend?
        if let fullHandle = config.fullHandle {
            let tuistAnalyticsServerBackend = TuistAnalyticsServerBackend(
                fullHandle: fullHandle,
                url: url
            )
            let dispatcher = TuistAnalyticsDispatcher(backend: tuistAnalyticsServerBackend)
            try TuistAnalytics.bootstrap(dispatcher: dispatcher)
            backend = tuistAnalyticsServerBackend
        } else {
            backend = nil
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
            let command = try parseAsRoot(processedArguments)
            executeCommand = {
                logFilePathDisplayStrategy = (command as? LogConfigurableCommand)?
                    .logFilePathDisplayStrategy ?? logFilePathDisplayStrategy

                let trackableCommand = TrackableCommand(
                    command: command,
                    commandArguments: processedArguments
                )
                try await trackableCommand.run(
                    backend: backend
                )
            }
        } catch {
            parsingError = error
            executeCommand = {
                try await executeTask(with: processedArguments)
            }
        }

        do {
            try await executeCommand()
            outputCompletion(logFilePath: logFilePath, shouldOutputLogFilePath: logFilePathDisplayStrategy == .always)
        } catch {
            onError(parsingError ?? error, isParsingError: parsingError != nil, logFilePath: logFilePath)
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

        if let clientError = error as? ClientError, clientError.underlyingError is ServerClientAuthenticationError {
            // swiftlint:disable:next force_cast
            errorAlertMessage = "\((clientError.underlyingError as! ServerClientAuthenticationError).description)"
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
            // Exit cleanly
            exit(withError: error)
        } else if let localizedError = error as? LocalizedError {
            errorAlertMessage = "\(localizedError.errorDescription ?? localizedError.localizedDescription)"
        } else {
            errorAlertMessage = "\((error as CustomStringConvertible).description)"
        }

        outputCompletion(logFilePath: logFilePath, shouldOutputLogFilePath: true, beforeLogsLine: {
            if let errorAlertMessage {
                ServiceContext.current?.ui?.error(.alert(errorAlertMessage, nextSteps: errorAlertNextSteps))
            }
        })
        _exit(exitCode)
    }

    private static func outputCompletion(
        logFilePath: AbsolutePath,
        shouldOutputLogFilePath: Bool,
        beforeLogsLine: () -> Void = {}
    ) {
        print("\n")
        ServiceContext.current?.alerts?.print()
        beforeLogsLine()
        if shouldOutputLogFilePath {
            outputLogFilePath(logFilePath)
        }
    }

    private static func outputLogFilePath(_ logFilePath: AbsolutePath) {
        ServiceContext.current?.logger?.info("\nLogs are available at \(logFilePath.pathString)")
    }

    private static func executeTask(with processedArguments: [String]) async throws {
        try await TuistService().run(
            arguments: processedArguments,
            tuistBinaryPath: processArguments()!.first!
        )
    }

    // MARK: - Helpers

    static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(ProcessInfo.processInfo.arguments)
        return arguments.filter { $0 != "--verbose" && $0 != "--quiet" }
    }
}
