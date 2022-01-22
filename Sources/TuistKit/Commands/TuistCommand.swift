import ArgumentParser
import Foundation
import TuistAnalytics
import TuistSupport

public struct TuistCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tuist",
            abstract: "Generate, build and test your Xcode projects.",
            subcommands: [
                BuildCommand.self,
                CacheCommand.self,
                CleanCommand.self,
                DependenciesCommand.self,
                DumpCommand.self,
                EditCommand.self,
                ExecCommand.self,
                FocusCommand.self,
                GenerateCommand.self,
                GraphCommand.self,
                InitCommand.self,
                CloudCommand.self,
                LintCommand.self,
                MigrationCommand.self,
                RunCommand.self,
                ScaffoldCommand.self,
                SigningCommand.self,
                TestCommand.self,
                VersionCommand.self,
            ]
        )
    }

    @Flag(
        name: [.customLong("help-env")],
        help: "Display subcommands to manage the environment tuist versions."
    )
    var isTuistEnvHelp: Bool = false

    public static func main(_ arguments: [String]? = nil) async {
        let errorHandler = ErrorHandler()
        var command: ParsableCommand
        do {
            let processedArguments = Array(processArguments(arguments)?.dropFirst() ?? [])
            if processedArguments.first == ScaffoldCommand.configuration.commandName {
                try ScaffoldCommand.preprocess(processedArguments)
            }
            if processedArguments.first == InitCommand.configuration.commandName {
                try InitCommand.preprocess(processedArguments)
            }
            if processedArguments.first == ExecCommand.configuration.commandName {
                try ExecCommand.preprocess(processedArguments)
            }
            command = try parseAsRoot(processedArguments)
        } catch {
            let exitCode = exitCode(for: error).rawValue
            if exitCode == 0 {
                logger.info("\(fullMessage(for: error))")
            } else {
                logger.error("\(fullMessage(for: error))")
            }
            _exit(exitCode)
        }
        do {
            try await execute(command)
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
            _exit(exitCode(for: error).rawValue)
        } catch {
            // Exit cleanly
            if exitCode(for: error).rawValue == 0 {
                exit(withError: error)
            } else {
                errorHandler.fatal(error: UnhandledError(error: error))
                _exit(exitCode(for: error).rawValue)
            }
        }
    }

    private static func execute(_ command: ParsableCommand) async throws {
        var command = command
        if Environment.shared.isStatsEnabled {
            let trackableCommand = TrackableCommand(command: command)
            try await trackableCommand.run()
        } else {
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.runAsync()
            } else {
                try command.run()
            }
        }
    }

    // MARK: - Helpers

    static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(ProcessInfo.processInfo.arguments)
        return arguments.filter { $0 != "--verbose" }
    }
}
