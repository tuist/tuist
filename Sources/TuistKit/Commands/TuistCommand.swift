import Foundation
import ArgumentParser
import TuistSupport

public struct TuistCommand: ParsableCommand {
    public init() { }
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "tuist",
                             abstract: "Generate, build and test your Xcode projects.",
                             subcommands: [GenerateCommand.self])
    }
    
    public static func main(_ arguments: [String]? = nil) -> Never {
        let errorHandler = ErrorHandler()
        let command: ParsableCommand
        do {
             command = try parseAsRoot(arguments)
        } catch {
            logger.error("\(fullMessage(for: error))")
            _exit(exitCode(for: error).rawValue)
        }
        do {
            try command.run()
            exit()
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
        } catch {
            errorHandler.fatal(error: UnhandledError(error: error))
        }
    }
}
