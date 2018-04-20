import Basic
import Foundation
import Utility

/// Registry that contains all the commands.
public final class CommandRegistry {
    // Argument parser.
    private let parser: ArgumentParser

    // Registered commands.
    var commands: [Command] = []

    /// Returns the process arguments.
    private let processArguments: () -> [String]

    /// Initialies the registry.
    ///
    /// - Parameters:
    ///   - usage: tool usage.
    ///   - overview: tool  overview.
    public init(usage: String,
                overview: String,
                processArguments: @escaping () -> [String] = CommandRegistry.processArguments) {
        parser = ArgumentParser(usage: usage, overview: overview)
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
    public func register(command: Command.Type) {
        commands.append(command.init(parser: parser))
    }

    /// Runs the command line interface.
    public func run() {
        do {
            let parsedArguments = try parse()
            try process(arguments: parsedArguments)
        } catch let error as ArgumentParserError {
            print(error.description)
        } catch let error {
            print(error.localizedDescription)
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
