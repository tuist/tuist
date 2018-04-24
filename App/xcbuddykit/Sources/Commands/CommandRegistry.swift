import Basic
import Foundation
import Utility

/// Registry that contains all the commands.
public final class CommandRegistry {
    // Argument parser.
    private let parser: ArgumentParser

    /// Printer.
    private let printer: Printing

    // Registered commands.
    var commands: [Command] = []

    /// Error handler.
    let errorHandler: CommandLineErrorHandling
    
    /// Returns the process arguments.
    private let processArguments: () -> [String]

<<<<<<< HEAD
    /// Initializes the command registry
    public init(processArguments: @escaping () -> [String] = CommandRegistry.processArguments) {
        printer = Printer()
        parser = ArgumentParser(usage: "<command> <options>",
                                overview: "Your Xcode buddy")
        self.processArguments = processArguments
        register(command: InitCommand.self)
        register(command: GenerateCommand.self)
        register(command: UpdateCommand.self)
        register(command: DumpCommand.self)
=======
    /// Initialies the registry.
    ///
    /// - Parameters:
    ///   - usage: tool usage.
    ///   - errorHandler: error handler.
    ///   - overview: tool  overview.
    public init(usage: String,
                overview: String,
                errorHandler: CommandLineErrorHandling,
                processArguments: @escaping () -> [String] = CommandRegistry.processArguments) {
        parser = ArgumentParser(usage: usage, overview: overview)
        self.processArguments = processArguments
        self.errorHandler = errorHandler
>>>>>>> [error-handler] Replace Sentry with Bugsnag
    }

    /// Returns the process arguments
    ///
    /// - Returns: process arguments.
    public static func processArguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }

    /// Register a new command.
    ///
    /// - Parameter command: command type.
    func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    /// Runs the command line interface.
    public func run() {
        errorHandler.run {
            let parsedArguments = try parse()
            try process(arguments: parsedArguments)
<<<<<<< HEAD
        } catch let error as ArgumentParserError {
            printer.print(errorMessage: error.localizedDescription)
            exit(1)
        } catch let error as CustomStringConvertible {
            printer.print(errorMessage: error.description)
            exit(1)
        } catch {
            printer.print(errorMessage: error.localizedDescription)
            exit(1)
=======
>>>>>>> [error-handler] Replace Sentry with Bugsnag
        }
    }

    /// Parses the CLI arguments that have been passed using the parser.
    ///
    /// - Returns: parsing result.
    /// - Throws: an error if the parsing fails.
    private func parse() throws -> ArgumentParser.Result {
        let arguments = Array(processArguments().dropFirst())
        return try parser.parse(arguments)
    }

    /// Process the parsing result.
    ///
    /// - Parameter arguments: parsing result.
    /// - Throws: an error if the output cannot be processed
    private func process(arguments: ArgumentParser.Result) throws {
        guard let subparser = arguments.subparser(parser),
            let command = commands.first(where: { $0.command == subparser }) else {
            parser.printUsage(on: stdoutStream)
            return
        }
        try command.run(with: arguments)
    }
}
