import ArgumentParser
import Foundation
import TuistAnalytics
import TuistSupport

public struct TuistCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "tuist",
                             abstract: "Generate, build and test your Xcode projects.",
                             subcommands: [
                                 GenerateCommand.self,
                                 UpCommand.self,
                                 FocusCommand.self,
                                 EditCommand.self,
                                 SecretCommand.self,
                                 DumpCommand.self,
                                 GraphCommand.self,
                                 LintCommand.self,
                                 VersionCommand.self,
                                 BuildCommand.self,
                                 TestCommand.self,
                                 CreateIssueCommand.self,
                                 ScaffoldCommand.self,
                                 InitCommand.self,
                                 CloudCommand.self,
                                 CacheCommand.self,
                                 SigningCommand.self,
                                 MigrationCommand.self,
                                 CleanCommand.self,
                                 DocCommand.self,
                                 DependenciesCommand.self,
                             ])
    }

    @Flag(
        name: [.customLong("help-env")],
        help: "Display subcommands to manage the environment tuist versions."
    )
    var isTuistEnvHelp: Bool = false

    public static func main(_ arguments: [String]? = nil) -> Never {
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
            command = try parseAsRoot(processedArguments)
        } catch {
            let exitCode = self.exitCode(for: error).rawValue
            if exitCode == 0 {
                logger.info("\(fullMessage(for: error))")
            } else {
                logger.error("\(fullMessage(for: error))")
            }
            _exit(exitCode)
        }
        do {
            try execute(command)
            exit()
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

    private static func execute(_ command: ParsableCommand) throws {
        var command = command
        guard Environment.shared.isStatsEnabled else {
            try command.run()
            return
        }
        let commandCompletionGroup = DispatchGroup()
        commandCompletionGroup.enter()
        let trackableCommand = TrackableCommand(command: command)
        try trackableCommand.run {
            commandCompletionGroup.leave()
        }
        let maximumWaitingTime = DispatchTimeInterval.seconds(2)
        // Block Tuist to wait until the event is persisted, otherwise it could get lost
        // Note: Tuist is not waiting for the event to be successfully sent, but only persisted
        // Set 2 seconds as a parachute timeout in case something goes wrong and the event is not persisted
        _ = commandCompletionGroup.wait(timeout: DispatchTime.now() + maximumWaitingTime)
    }

    // MARK: - Helpers

    static func processArguments(_ arguments: [String]? = nil) -> [String]? {
        let arguments = arguments ?? Array(ProcessInfo.processInfo.arguments)
        return arguments.filter { $0 != "--verbose" }
    }
}
