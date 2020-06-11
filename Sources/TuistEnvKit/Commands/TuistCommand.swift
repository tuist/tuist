import ArgumentParser
import Foundation
import TuistSupport

public struct TuistCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "tuist",
                             abstract: "Manage the environment tuist versions",
                             subcommands: [
                                 LocalCommand.self,
                                 BundleCommand.self,
                                 UpdateCommand.self,
                                 InstallCommand.self,
                                 UninstallCommand.self,
                                 VersionCommand.self,
                             ])
    }

    public static func main(_: [String]? = nil) -> Never {
        let errorHandler = ErrorHandler()
        do {
            let processedArguments = processArguments()
            if processedArguments.dropFirst().first == "--help-env" {
                throw CleanExit.helpRequest(self)
            } else if let parsedArguments = try parse() {
                var command = try parseAsRoot(parsedArguments)
                try command.run()
            } else {
                try CommandRunner().run()
            }
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

    // MARK: - Helpers

    private static func parse() throws -> [String]? {
        let arguments = Array(processArguments().dropFirst())
        guard let firstArgument = arguments.first else { return nil }
        let containsCommand = configuration.subcommands.map { $0.configuration.commandName }.contains(firstArgument)
        if containsCommand {
            return arguments
        }
        return nil
    }

    // MARK: - Static

    static func processArguments() -> [String] {
        CommandRunner.arguments()
    }
}
