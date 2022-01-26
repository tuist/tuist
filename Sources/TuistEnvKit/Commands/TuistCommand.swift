import ArgumentParser
import Foundation
import TuistSupport

public struct TuistCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tuist",
            abstract: "Manage the environment tuist versions",
            subcommands: [
                LocalCommand.self,
                BundleCommand.self,
                UpdateCommand.self,
                InstallCommand.self,
                UninstallCommand.self,
                VersionCommand.self,
            ]
        )
    }

    public static func main(_: [String]? = nil) {
        let errorHandler = ErrorHandler()
        let processedArguments = processArguments()

        // Help env
        if processedArguments.dropFirst().first == "--help-env" {
            let error = CleanExit.helpRequest(self)
            exit(withError: error)
        }

        // Parse the command
        var command: ParsableCommand?
        do {
            if let parsedArguments = try parse() {
                command = try parseAsRoot(parsedArguments)
            }
        } catch {
            let exitCode = exitCode(for: error).rawValue
            if exitCode == 0 {
                logger.info("\(fullMessage(for: error))")
            } else {
                logger.error("\(fullMessage(for: error))")
            }
            _exit(exitCode)
        }

        // Run the command
        do {
            if var command = command {
                try command.run()
            } else {
                try CommandRunner().run()
            }
            _exit(0)
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
        // swiftformat:disable preferKeyPath
        let containsCommand = configuration.subcommands.map { $0.configuration.commandName }.contains(firstArgument)
        // swiftformat:enable preferKeyPath
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
