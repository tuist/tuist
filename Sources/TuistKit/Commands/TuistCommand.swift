@_exported import ArgumentParser
import Foundation
import OpenAPIRuntime
import Path
import TuistAnalytics
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
                        RunCommand.self,
                        ScaffoldCommand.self,
                        TestCommand.self,
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
                        ProjectCommand.self,
                        OrganizationCommand.self,
                        AuthCommand.self,
                        SessionCommand.self,
                        LogoutCommand.self,
                    ]
                ),
            ]
        )
    }

    public static func main(
        _ arguments: [String]? = nil,
        parseAsRoot: ((_ arguments: [String]?) throws -> ParsableCommand) = Self.parseAsRoot
    ) async throws {
        let path: AbsolutePath
        if let argumentIndex = CommandLine.arguments.firstIndex(of: "--path") {
            path = try AbsolutePath(validating: CommandLine.arguments[argumentIndex + 1], relativeTo: .current)
        } else {
            path = .current
        }

        let backend: TuistAnalyticsBackend?
        let config = try await ConfigLoader().loadConfig(path: path)
        if let fullHandle = config.fullHandle {
            backend = TuistAnalyticsServerBackend(
                fullHandle: fullHandle,
                url: config.url
            )
        } else {
            backend = nil
        }
        let dispatcher = TuistAnalyticsDispatcher(backend: backend)
        try TuistAnalytics.bootstrap(dispatcher: dispatcher)

        let errorHandler = ErrorHandler()
        let executeCommand: () async throws -> Void
        let processedArguments = Array(processArguments(arguments)?.dropFirst() ?? [])
        var parsedError: Error?
        do {
            if processedArguments.first == ScaffoldCommand.configuration.commandName {
                try await ScaffoldCommand.preprocess(processedArguments)
            }
            if processedArguments.first == InitCommand.configuration.commandName {
                try await InitCommand.preprocess(processedArguments)
            }
            let command = try parseAsRoot(processedArguments)
            executeCommand = {
                let trackableCommand = TrackableCommand(
                    command: command,
                    commandArguments: processedArguments
                )
                try await trackableCommand.run()
            }
        } catch {
            parsedError = error
            executeCommand = {
                try await executeTask(with: processedArguments)
            }
        }

        do {
            defer { WarningController.shared.flush() }
            try await executeCommand()
        } catch let error as FatalError {
            WarningController.shared.flush()
            errorHandler.fatal(error: error)
            _exit(exitCode(for: error).rawValue)
        } catch let error as ClientError where error.underlyingError is ServerClientAuthenticationError {
            WarningController.shared.flush()
            // swiftlint:disable:next force_cast
            logger.error("\((error.underlyingError as! ServerClientAuthenticationError).description)")
            _exit(exitCode(for: error).rawValue)
        } catch {
            WarningController.shared.flush()
            if let parsedError {
                handleParseError(parsedError)
            }
            // Exit cleanly
            if exitCode(for: error).rawValue == 0 {
                exit(withError: error)
            } else {
                errorHandler.fatal(error: UnhandledError(error: error))
                _exit(exitCode(for: error).rawValue)
            }
        }
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
            logger.notice("\(fullMessage(for: error))")
        } else {
            logger.error("\(fullMessage(for: error))")
        }
        _exit(exitCode)
    }

    // MARK: - Helpers

    static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(ProcessInfo.processInfo.arguments)
        return arguments.filter { $0 != "--verbose" }
    }
}
