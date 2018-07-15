import Basic
import Foundation
import Utility
import xpmcore

public final class CommandRegistry {

    // MARK: - Attributes

    // Argument parser.
    let parser: ArgumentParser

    /// Commands
    var commands: [Command] = []

    /// Error handler.
    private let errorHandler: ErrorHandling

    /// Returns the process arguments.
    private let processArguments: () -> [String]

    /// Command runner.
    private let commandRunner: CommandRunning

    /// Default constructor.
    public convenience init() {
        self.init(processArguments: CommandRegistry.processArguments)
    }

    /// Initializes the command registrry with its attributes.
    ///
    /// - Parameters:
    ///   - processArguments: process arguments.
    ///   - errorHandler: error handler.
    ///   - commandRunner: command runner.
    ///   - commands: list of commands to register.
    init(processArguments: @escaping () -> [String],
         errorHandler: ErrorHandling = ErrorHandler(),
         commandRunner: CommandRunning = CommandRunner(),
         commands: [Command.Type] = []) {
        parser = ArgumentParser(commandName: "xpm",
                                usage: "<command> <options>",
                                overview: "Manage the environment xpm versions.",
                                seeAlso: "http://docs.xcodepm.com/")
        self.processArguments = processArguments
        self.errorHandler = errorHandler
        self.commandRunner = commandRunner
        commands.forEach(register)
    }

    /// Runs the CLI using the process arguments.
    public func run() {
        do {
            if let parsedArguments = try parse() {
                try process(arguments: parsedArguments)
            } else {
                try commandRunner.run()
            }
        } catch let error as FatalError {
            errorHandler.fatal(error: error)
        } catch {
            errorHandler.fatal(error: UnhandledError(error: error))
        }
    }

    /// Parses the process arguments and returns the result if the command
    /// is a valid xpmenv command. Otherwise, it returns nil, meaning that
    /// the command should be proxied to xpm.
    ///
    /// - Returns: parsing result if the command is a xpmenv command.
    /// - Throws: an error if the command parsing fails (e.g. wrong arguments).
    private func parse() throws -> ArgumentParser.Result? {
        let arguments = Array(processArguments().dropFirst())
        guard let firstArgument = arguments.first else { return nil }
        if commands.map({ type(of: $0).command }).contains(firstArgument) {
            return try parser.parse(arguments)
        }
        return nil
    }

    /// Registers a new command.
    ///
    /// - Parameter command: command type to be registered.
    fileprivate func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    /// Process the parsing result.
    ///
    /// - Parameter arguments: parsing result.
    /// - Throws: an error if the output cannot be processed
    fileprivate func process(arguments: ArgumentParser.Result) throws {
        let subparser = arguments.subparser(parser)!
        let command = commands.first(where: { type(of: $0).command == subparser })!
        try command.run(with: arguments)
    }

    // MARK: - Static

    /// Returns the process arguments
    ///
    /// - Returns: process arguments.
    static func processArguments() -> [String] {
        return Array(ProcessInfo.processInfo.arguments)
    }
}
