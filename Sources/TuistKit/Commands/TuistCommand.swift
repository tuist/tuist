import ArgumentParser
import Foundation
import TuistSupport

public struct TuistCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "tuist",
                             abstract: "Generate, build and test your Xcode projects.",
                             subcommands: [
                                GenerateCommand.self,
                                ScaffoldCommand.self,
                                InitCommand.self,
        ])
    }

    public static func main(_ arguments: [String]? = nil) -> Never {
        let errorHandler = ErrorHandler()
        let command: ParsableCommand
        do {
            let processedArguments = processArguments(arguments)
            if processedArguments?.first == ScaffoldCommand.configuration.commandName {
                try ScaffoldCommand.preprocess(processedArguments)
            }
            if processedArguments?.first == InitCommand.configuration.commandName {
                try InitCommand.preprocess(processedArguments)
            }
            command = try parseAsRoot(processedArguments!)
        } catch {
            logger.error("\(fullMessage(for: error))")
            _exit(exitCode(for: error).rawValue)
        }
        do {
            try command.run()
            exit()
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
            _exit(exitCode(for: error).rawValue)
        } catch {
            errorHandler.fatal(error: UnhandledError(error: error))
            _exit(exitCode(for: error).rawValue)
        }
    }

    // MARK: - Helpers

    private static func processArguments(_ arguments: [String]?) -> [String]? {
        let arguments = arguments ?? Array(CommandLine.arguments.dropFirst())
        return arguments.filter { $0 != "--verbose" }
    }
}
