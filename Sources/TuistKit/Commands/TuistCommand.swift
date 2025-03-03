@_exported import ArgumentParser
import Foundation
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
            abstract: "Generate, build and test your Xcode projects.",
            subcommands: [],
            groupedSubcommands: [
                CommandGroup(
                    name: "Start",
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

        let config = try await ConfigLoader(warningController: WarningController.shared).loadConfig(path: path)
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

        let errorHandler = ErrorHandler()
        let executeCommand: () async throws -> Void
        let processedArguments = Array(processArguments(arguments)?.dropFirst() ?? [])
        var parsedError: Error?
        var logFilePathDisplayStrategy: LogFilePathDisplayStrategy = .onError

        do {
            if processedArguments.first == ScaffoldCommand.configuration.commandName {
                try await ScaffoldCommand.preprocess(processedArguments)
            }
            if processedArguments.first == InitCommand.configuration.commandName {
                try await InitCommand.preprocess(processedArguments)
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
            parsedError = error
            executeCommand = {
                try await executeTask(with: processedArguments)
            }
        }

        do {
            try await executeCommand()
            outputCompletion(logFilePath: logFilePath, shouldOutputLogFilePath: logFilePathDisplayStrategy == .always)
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
            self.outputCompletion(logFilePath: logFilePath, shouldOutputLogFilePath: true)
            _exit(exitCode(for: error).rawValue)
        } catch let error as ClientError where error.underlyingError is ServerClientAuthenticationError {
            // swiftlint:disable:next force_cast
            ServiceContext.current?.logger?.error("\((error.underlyingError as! ServerClientAuthenticationError).description)")
            outputCompletion(logFilePath: logFilePath, shouldOutputLogFilePath: true)
            _exit(exitCode(for: error).rawValue)
        } catch {
            if let parsedError {
                handleParseError(parsedError)
            }

            // Exit cleanly
            if exitCode(for: error).rawValue == 0 {
                exit(withError: error)
            } else {
                errorHandler.fatal(error: UnhandledError(error: error))
                outputCompletion(logFilePath: logFilePath, shouldOutputLogFilePath: true)
                _exit(exitCode(for: error).rawValue)
            }
        }
    }

    private static func outputCompletion(logFilePath: AbsolutePath, shouldOutputLogFilePath: Bool) {
        WarningController.shared.flush()
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

    private static func handleParseError(_ error: Error) -> Never {
        let exitCode = exitCode(for: error).rawValue
        if exitCode == 0 {
            ServiceContext.current?.logger?.notice("\(fullMessage(for: error))")
        } else {
            ServiceContext.current?.logger?.error("\(fullMessage(for: error))")
        }
        _exit(exitCode)
    }

    // MARK: - Helpers

    static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(ProcessInfo.processInfo.arguments)
        return arguments.filter { $0 != "--verbose" && $0 != "--quiet" }
    }
}
