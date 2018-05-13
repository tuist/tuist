import Basic
import Foundation
import Utility

/// Registry that contains all the commands.
public final class CommandRegistry {
    // Argument parser.
    let parser: ArgumentParser

    /// Context.
    private let context: Contexting

    /// Command check.
    private let commandCheck: CommandChecking

    // Registered commands.
    var commands: [Command] = []

    /// Returns the process arguments.
    private let processArguments: () -> [String]

    /// Public ocnstructor that takes no arguments.
    public convenience init() {
        self.init(context: Context(),
                  commandCheck: CommandCheck(),
                  processArguments: CommandRegistry.processArguments)
        register(command: InitCommand.self)
        register(command: GenerateCommand.self)
        register(command: UpdateCommand.self)
        register(command: DumpCommand.self)
        register(command: VersionCommand.self)
    }

    /// Initializes the command registry
    init(context: Contexting,
         commandCheck: CommandChecking,
         processArguments: @escaping () -> [String]) {
        self.commandCheck = commandCheck
        self.context = context
        parser = ArgumentParser(usage: "<command> <options>",
                                overview: "Your Xcode buddy")
        self.processArguments = processArguments
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
    public func run() throws {
        context.errorHandler.try {
            let parsedArguments = try parse()
            try process(arguments: parsedArguments)
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
            let command = commands.first(where: { type(of: $0).command == subparser }) else {
            parser.printUsage(on: stdoutStream)
            return
        }
        try commandCheck.check(command: type(of: command).command)
        command.run(with: arguments)
    }
}
